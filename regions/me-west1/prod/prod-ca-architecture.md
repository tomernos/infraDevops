# Production Platform CA architecture

**Status: design + CODE IMPLEMENTED (2026-07-22). Nothing provisioned.** This describes how the
Platform CA (the authority that issues end-entity **PDF-signing certificates** to
users) moves from the dev-only extractable local CA to a real managed CA in
production, and exactly which code/variables/IAM change.

> **Implemented (overnight run 2026-07-22) — code only, no apply:**
> - **Engine** (`feat/prod-ca-provider`): `backend/src/crypto/providers/gcpCasProvider.js`
>   (CAS provider, lazy-required), `caProvider.js` unblocks `gcp_cas`, `caProvider.test.js`
>   updated (16/16 pass without the dep installed), `package.json` adds
>   `@google-cloud/security-private-ca`. ⚠️ run `npm install` from **PowerShell** to sync the
>   lockfile (WSL NTFS blocks it) before that branch's CI.
> - **Infra** (`feat/prod-environment`): `modules/private-ca` (CAS pool + self-signed root +
>   `certificateRequester` IAM), `regions/me-west1/prod/private-ca/` stack, and prod `cloud-run`
>   wired `ca_provider="gcp_cas"` + `cas_ca_pool` from the new stack. `terraform validate` passes
>   on both modules.
> - **Remaining (Tomer / cloud):** apply; enable CAS **Data Access audit logs**; optionally add the
>   subordinate-CA tier (below) via the CSR sign+activate flow; set `CAS_ISSUING_CA` if pinning a
>   subordinate. The single self-signed root already issues end-entity certs — the subordinate is a
>   rotation-hygiene enhancement, not a blocker.

## What the Platform CA is (and is NOT)
- **Is:** the issuer of short-lived end-entity certs used to sign users' PDFs
  (Adobe PDF-signing EKU `1.2.840.113583.1.1.5` + emailProtection). One cert per
  signer, bound to their RSA public key.
- **Is NOT:** the trust-DEK KEK or the sign-HMAC key — those are already Cloud KMS
  (`security` module) and are unaffected. This doc is only about X.509 issuance.

## Current abstraction (already pluggable — the seam exists)
Issuance is behind a provider interface; **only the provider implementation changes**
between dev and prod. Callers never branch on environment.

| Location | Role |
|---|---|
| `backend/src/crypto/caProvider.js` | Selector + **fail-closed** guardrails. `getCaProvider()` dispatches on `CA_PROVIDER`; `validateCaConfig()` is the startup hook. Already rejects `gcp_cas` with *"not implemented"* and forbids `local` unless `APP_ENV∈{local,dev,test}` **and** `ALLOW_LOCAL_CA=true`. |
| `backend/src/crypto/providers/localCaProvider.js` | **DEV-ONLY.** Extractable CA key in app memory (`PLATFORM_CA_CERT_PEM`/`PLATFORM_CA_KEY_PEM` via Secret Manager), issues with `node-forge`. |
| `backend/src/crypto/pkiService.js` | Calls `getCaProvider().issueCertificate({subject, publicKeyPem, validityDays})` → `{certPem, caChainPem, expiresAt, providerRef}`. Persists the returned cert. **Provider-agnostic.** |
| `modules/cloud-run` (`main.tf`/`variables.tf`) | Injects `CA_PROVIDER`, `APP_ENV`, `ALLOW_LOCAL_CA`, and (local only) the two `PLATFORM_CA_*` secret env refs. TF-level guardrail already refuses `allow_local_ca` outside dev. |
| `modules/security` (`enable_local_platform_ca_secrets`) | Creates the local CA PEM secrets. **Off in prod** — prod has no extractable CA material. |

The **contract a prod provider must satisfy** is exactly:
```
issueCertificate({ subject:{commonName,email,organizationName}, publicKeyPem, validityDays })
  → { certPem, caChainPem, expiresAt, providerRef }
validate()   // startup: prove the CA is reachable/authorized; throw otherwise
```

## Recommended production provider: Google Cloud Certificate Authority Service (CAS)
**Recommendation: GCP CAS (Enterprise tier), private/internal CA pool.** It keeps CA
private keys in Google-managed HSMs (non-extractable — closes the local provider's one
real weakness), issues via API (drop-in for `issueCertificate`), and emits Cloud Audit
Logs for every issuance/revocation. It is the same-cloud, least-new-surface option.

### Options considered
| Option | Key custody | Fit | Verdict |
|---|---|---|---|
| **GCP CAS** | Google HSM, non-extractable | Native API, IAM, audit logs, in-project | **Recommended** |
| Local CA in KMS/HSM (self-host issuance, sign with a KMS asymmetric key) | KMS non-extractable | Reuse `node-forge` cert assembly, sign via KMS `asymmetricSign`; you run CRL/OCSP/lifecycle yourself | Fallback if CAS is unavailable/too costly; **more code + ops** |
| External CA (public/eIDAS QTSP) | Provider HSM | Needed only for legally-qualified/public-trust signatures (see legal-sector plan) | Later, if regulator-trust is required — orthogonal to this seam |

Trade-off summary: CAS = least code, managed lifecycle/HSM/audit, ~per-cert + CA-pool
cost. KMS-self-signed = no CAS dependency and cheaper per cert, but you own revocation
infrastructure and rotation. Public QTSP = only when signatures must be externally
trusted; heavier onboarding. **Start with CAS; the provider seam makes switching a
one-file change.**

## Integration path (CAS) — exact changes
1. **New provider** `backend/src/crypto/providers/gcpCasProvider.js` implementing the
   contract above via `@google-cloud/security-center`/`@google-cloud/private-ca`
   (`CertificateAuthorityServiceClient.createCertificate`). Map `subject`+`publicKeyPem`
   to a CAS `Certificate` with the same profile (PDF-signing EKU, 1y validity, digital
   signature + non-repudiation). Return CAS's PEM + issuer chain + `notAfter`;
   `providerRef = <cas-certificate-resource-name>`.
2. **Wire it in** `caProvider.js`: replace the `gcp_cas` throw with
   `return gcpCasProvider;` (keep the fail-closed guards; `gcp_cas` needs **no**
   `ALLOW_LOCAL_CA`). `validate()` calls `getCaPool`/`get` to prove access at boot.
3. **New dependency:** `@google-cloud/private-ca` in `backend/package.json` (audit + lock).
4. **cloud-run module:** set `ca_provider="gcp_cas"`, `allow_local_ca=false`, and add
   non-secret env `CAS_CA_POOL` (pool resource name) + `CAS_LOCATION`. No PEM secrets.
5. **security module:** `enable_local_platform_ca_secrets=false` (already set in prod).
6. **New infra:** a `modules/private-ca` (CAS CA pool + root/subordinate CA) — see
   Hierarchy. Grant the **runtime** SA `sa-api` `roles/privateca.certificateRequester`
   (issue only — **not** admin). CA admin/rotation is a human/break-glass role, never the
   app SA.
7. **prod env value:** the CA pool id in `env.hcl` (later the YAML values repo).

### Hierarchy
```
Root CA (CAS, Enterprise, HSM)         — long-lived (e.g. 10y), issues subordinates only, kept "staged"/offline-ish
  └─ Subordinate "Platform Signing CA" — medium-lived (e.g. 3y), online issuer in the CA pool
        └─ end-entity signer certs      — short-lived (1y), one per user signature identity
```
Rationale: a compromised/expired subordinate is replaced without moving the root of
trust; end-entity certs stay short-lived so revocation exposure is bounded.

### Lifecycle / rotation
- **End-entity:** 1y (`validityDays` default, unchanged). Re-issued on demand; no rotation
  ceremony.
- **Subordinate:** rotate before expiry by activating a new subordinate in the pool and
  flipping the issuing pool/CA id (one env value); overlap the two so in-flight chains stay
  valid. `caChainPem` returned per-issuance means clients always get the current chain.
- **Root:** rare; staged root rotation with cross-signing if it ever changes.

### Revocation
- CAS supports `revokeCertificate` + managed **CRL** (and optional OCSP). Add a
  `revokeCertificate(providerRef, reason)` to the provider contract when the app needs to
  revoke (e.g. on user off-boarding / key compromise). Store `providerRef` (already
  returned) so revocation targets the exact CAS resource. CRL distribution point is set on
  the CA pool; end-entity certs carry the CDP automatically.

### Backup / DR
- Root/subordinate **private keys never leave Google HSM** — nothing to back up
  (custody = Google). Back up *configuration*: CA pool + CA definitions are in Terraform
  (`modules/private-ca`), state in the prod state bucket. Issued-cert **records** live in
  Postgres (already in `pdf_sign_*` tables, covered by the prod DB PITR+30d backups). CAS
  retains issued-cert metadata server-side.

### Auditing
- Every CAS `createCertificate`/`revokeCertificate` is a **Cloud Audit Log** (Data Access)
  entry — attributable to `sa-api`. Enable Data Access audit logs for CAS in the prod
  project. App-side, `pdf_sign_events` already records issuance events (KMS-HMAC sealed).
  Two independent trails (Google audit + app DB) — reconcilable via `providerRef`.

## Affected surface (checklist for the implementation PR)
- **Modules:** new `modules/private-ca`; `modules/cloud-run` (env vars, drop PEM secrets in prod path); `modules/security` (`enable_local_platform_ca_secrets=false`).
- **Variables:** `ca_provider`, `allow_local_ca` (exist); new `cas_ca_pool`, `cas_location`; remove `PLATFORM_CA_*` from prod.
- **IAM:** `sa-api` → `roles/privateca.certificateRequester` on the pool; separate admin role for humans; CAS Data Access audit logs on.
- **Services:** engine API (runtime); no new Cloud Run service.
- **Certs:** root + subordinate (CAS-managed); end-entity unchanged in profile.
- **Deps:** `@google-cloud/private-ca` (backend).
- **Code:** `providers/gcpCasProvider.js` (new); `caProvider.js` (unblock `gcp_cas`); `pkiService.js` unchanged; optional `revokeCertificate` addition.

## Guardrails preserved
Prod stays fail-closed: `local` is impossible (`APP_ENV=prod` fails the allowlist **and**
`allow_local_ca=false` is refused by the TF condition), and `gcp_cas` requires a reachable,
authorized pool at boot (`validate()` throws otherwise). No silent fallback between
providers — an unset/typo'd `CA_PROVIDER` refuses to start.

> Cross-ref: `ReferencesContext/sweptlock/plans/codex/decisions/adr-platform-ca-provider.md`
> (provider ADR) and `ReferencesContext/sweptlock/modules/legal-sector-analysis.md`
> (when public/eIDAS-qualified issuance is required instead of an internal CA).
