# SweptLock — Network Architecture

> How traffic flows in the dev environment (`sweptlock-dev-844f2`, region `me-west1`), why the
> pieces are arranged this way, and how to diagnose network problems yourself.
> Companion to the Terraform in `modules/networking`, `modules/cloud-run`, `modules/database`.

---

## 1. The mental model

The backend is a **serverless container** (Cloud Run). It is *not* inside the VPC by default —
it lives on Google's edge and is given a "foot" inside our private network so it can reach
private resources (the database). Everything in this doc is about **where each outbound call
goes** once it leaves the container.

The backend makes three kinds of outbound calls, and each takes a different road:

```
                      ┌─────────────────────────────────────────────┐
   Internet  ──HTTPS──▶  Cloud Run service  (swpt-mw1-dev-api)        │
   (clients)            │   public ingress, Firebase-auth at app layer │
                        └───────────────┬─────────────────────────────┘
                                        │  outbound
            ┌───────────────────────────┼─────────────────────────────┐
            │                           │                             │
   (A) to the DATABASE          (B) to GOOGLE APIs           (C) to the rest of
   private IP 10.137.96.3        Firebase / oauth2             the internet
            │                           │                             │
   Direct VPC Egress            Direct VPC Egress             Direct VPC Egress
   → subnet 10.11.0.0/20        → subnet → Cloud NAT          → subnet → Cloud NAT
   → VPC peering (PSA)          → internet                    → internet
   → Cloud SQL                  → www.googleapis.com          → third parties
```

**Key idea:** with `egress = ALL_TRAFFIC`, *all three* roads run through our VPC. Private
destinations (A) use the VPC peering; public destinations (B, C) leave through **Cloud NAT**.

---

## 2. The components

| Component | Name | Job |
|---|---|---|
| VPC network | `swpt-mw1-dev-vpc` | The private network. MTU 1460 (matches Cloud Run Direct VPC Egress). |
| Private subnet | `swpt-mw1-dev-vpc-subnet-private` `10.11.0.0/20` | Where Cloud Run's "foot" (Direct VPC Egress IP) and other workloads live. |
| Private Services Access range | `swpt-mw1-dev-vpc-psc-range` `10.137.96.0/20` | IP range **reserved for Google-managed services** (Cloud SQL) reachable over a VPC peering. |
| VPC peering | `servicenetworking-googleapis-com` | The bridge to Google's managed network where Cloud SQL actually runs. State must be `ACTIVE`. |
| Cloud SQL | `swpt-mw1-dev-sql-main` (private IP `10.137.96.3`) | PostgreSQL. **No public IP** — only reachable from inside the VPC. |
| Cloud Run service | `swpt-mw1-dev-api` | The backend. Uses **Direct VPC Egress** to get into the subnet. |
| Cloud Router | `swpt-mw1-dev-vpc-router` | Hosts the NAT (and would host BGP if we used Cloud VPN/Interconnect). |
| Cloud NAT | `swpt-mw1-dev-vpc-nat` | The **outbound internet door**. Lets workloads with *no public IP* reach the internet. Covers `ALL_SUBNETWORKS_ALL_IP_RANGES`. |
| Firewall | `…-fw-allow-iap-ssh`, `…-fw-allow-lb` | Ingress allow-rules (SSH via IAP, load-balancer health checks). Egress is allowed by GCP's implied rule. |

---

## 3. Egress modes (the setting that caused our incident)

The Cloud Run service has a `vpc_access.egress` setting. Two values matter:

| Mode | Private traffic (DB) | Public traffic (Google/internet) |
|---|---|---|
| `PRIVATE_RANGES_ONLY` | through the VPC ✅ | **bypasses the VPC** — uses Cloud Run's own default egress path |
| `ALL_TRAFFIC` (current) | through the VPC ✅ | **through the VPC → Cloud NAT → internet** |

We run **`ALL_TRAFFIC`**. The earlier `PRIVATE_RANGES_ONLY` setting let the database work (private)
but routed Firebase/Google calls down Cloud Run's default path, where they failed with
`Premature close` reaching `www.googleapis.com/oauth2/v4/token`. Routing those calls through our
own NAT fixed it. (See the incident log in §6.)

---

## 4. Security perspective — why `ALL_TRAFFIC` + NAT is a *good* posture

Sending all egress through our own NAT is not just a fix; it's a stronger security stance:

- **One controlled exit, not an opaque one.** With `PRIVATE_RANGES_ONLY`, public traffic left via
  a Google-managed path we don't see or control. With `ALL_TRAFFIC`, *every* outbound packet
  passes through **our** NAT — a single chokepoint we own.
- **Egress filtering becomes possible.** Because public traffic now traverses the VPC, our VPC
  **firewall egress rules** can allow/deny it. We can move toward "deny egress by default, allow
  only known destinations" — a real defense against data exfiltration and a compromised dependency
  phoning home. That was impossible when public traffic bypassed the VPC.
- **Observability / audit.** NAT logging + VPC Flow Logs give us a record of what the backend
  talks to. Useful for incident response and anomaly detection.
- **Stable egress identity (optional).** A NAT can pin a **static egress IP**, so partners/3rd-party
  APIs can allowlist *us*. (Ours is currently `AUTO_ONLY` = auto IPs that can change; reserve a
  static NAT IP if/when we need allowlisting.)
- **No new inbound exposure.** NAT is **outbound only**. It does not open any path *into* the
  service. Clients still reach the app only through the Cloud Run public HTTPS endpoint, where
  Firebase auth is enforced at the application layer. So this change widens nothing inbound.

**Trade-offs to keep in mind:** all egress now depends on the NAT (capacity + a potential single
point of failure), and NAT has per-port limits — at high scale, watch for **port exhaustion**
(symptom: intermittent outbound connection failures). Mitigation: more NAT IPs / tuned min-ports.

---

## 5. Diagnose it yourself — component → command cheat sheet

General commands (drop the flags; add `--project`/`--region` as needed):

| To check… | Component | Command |
|---|---|---|
| Is the DB reachable / its private IP & VPC | Cloud SQL | `gcloud sql instances describe` |
| Which network the DB is attached to | Cloud SQL | `gcloud sql instances describe` → `ipConfiguration.privateNetwork` |
| Is the peering to Google healthy | VPC peering | `gcloud compute networks peerings list` (want `ACTIVE`) |
| Does the reserved range cover the DB IP | Global address | `gcloud compute addresses list` |
| What egress mode is the service using | Cloud Run | `gcloud run services describe` → vpc-access annotations |
| Does the NAT cover the subnet | Cloud NAT | `gcloud compute routers nats describe` |
| What is the network MTU | VPC | `gcloud compute networks describe` |
| Firewall rules on the VPC | Firewall | `gcloud compute firewall-rules list` |
| What is the app actually erroring on | Cloud Run logs | `gcloud logging read` (filter the service) |

**Reading the symptom:**
- `ETIMEDOUT` → the packets never arrive (no route / firewall / wrong network). A *reachability* problem.
- `ECONNREFUSED` → reached the host, but nothing is listening (service down / restarting).
- `Premature close` / truncated responses → the connection opens but is cut off mid-reply — often an
  **egress-path** problem (the wrong road out) or an MTU mismatch.

---

## 6. Incident log

**2026-06-24 — Firebase `getUserByEmail` failing on Cloud Run (`/auth/check-user` 500).**
- Symptom: returning users "not recognized," bounced to signup.
- Root cause: `vpc_access.egress = PRIVATE_RANGES_ONLY` routed Firebase/Google calls down Cloud
  Run's default egress, which could not complete the TLS fetch of the OAuth token
  (`www.googleapis.com/oauth2/v4/token` → `Premature close` → `app/invalid-credential`).
  Database (private) was unaffected; `verifyIdToken` kept working off cached keys, which masked it.
- Fix: `egress = ALL_TRAFFIC` so Google calls leave through Cloud NAT (this file + `modules/cloud-run`).
- Also fixed alongside: `checkUser` no longer swallows the error / returns a misleading
  `exists:false` on failure (engine repo `authController.js`).

**Earlier (06-22→06-24) — `ETIMEDOUT 10.137.96.3:5432`.** Database connectivity outage (separate
from the above); see git history. Tables/migrations were always intact.
