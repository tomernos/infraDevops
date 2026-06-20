# Ephemeral GitHub Runner on Cloud Run (Android builds)

A **self-hosted GitHub Actions runner** that spins up **only when a build is queued**,
runs on a **Cloud Run Job** (8 vCPU / 32 GB — vs the GitHub-hosted 2-core/7 GB that
OOMs on our RN build), runs **one job**, then **scales to zero**. No persistent VM,
no idle cost, no EAS.

## Why
The React Native release/debug build (OpenSSL prefab + worklets/reanimated + new-arch
codegen) exceeds 7 GB on GitHub-hosted runners. Cloud Run Jobs give us 32 GB on demand.

## How it works

```
GitHub job (runs-on: [self-hosted, cloudrun, android])
      │  queued, no runner online
      ▼
GitHub  ──webhook: workflow_job=queued──▶  Dispatcher (Cloud Run Service, scales to 0)
                                              │ 1. verify webhook HMAC
                                              │ 2. POST /actions/runners/generate-jitconfig
                                              │ 3. run jobs execute  (JITCONFIG=<blob>)
                                              ▼
                                          Cloud Run Job  (8 vCPU / 32 GB, ephemeral)
                                              │ ./run.sh --jitconfig <blob>
                                              │ registers → runs THE job → gradle build
                                              │ uploads APK artifact → deregisters → exit
                                              ▼
                                          scale to zero
```

`--jitconfig` = a single-use, ephemeral runner registration. No long-lived tokens.

## Phases

| # | Deliverable | Status | Owner |
|---|---|---|---|
| 1 | **Runner image** (`Dockerfile`, `entrypoint.sh`, `cloudbuild.yaml`) | code done | you: build it |
| 2 | **Cloud Run Job** `swpt-mw1-dev-ci-runner` (32 GB, JITCONFIG override) | TODO | me |
| 3 | **Dispatcher** Cloud Run Service + GitHub App/PAT + webhook | TODO | me + you (GitHub) |
| 4 | `build-poc.yml` → `runs-on: [self-hosted, cloudrun, android]`; first live build | TODO | me + you |

## Phase 1 — build the runner image (you run)

Prereqs (one-time):
```bash
gcloud auth login                                  # token expired in WSL; re-auth
gcloud services enable cloudbuild.googleapis.com --project sweptlock-dev-844f2
```

Build + push (~15–25 min; the image is big):
```bash
cd ci-runner
gcloud builds submit --config cloudbuild.yaml \
  --project sweptlock-dev-844f2 --region me-west1 \
  --substitutions=_TAG=v1 .
```
Result: `me-west1-docker.pkg.dev/sweptlock-dev-844f2/swpt-mw1-dev-registry/ci-android-runner:v1`

## Decision needed before Phase 3 — how the dispatcher authenticates to GitHub

| Option | Pros | Cons |
|---|---|---|
| **GitHub App** (recommended) | Scoped, rotatable, no personal token, org-friendly | Create+install an App, store private key in Secret Manager |
| **Fine-grained PAT** | Fastest to stand up | Long-lived token (manual rotation), tied to your account |

Both need permission to **generate runner JIT configs** (`administration: write` on the repo).

## What you'll do in consoles (later phases)
- Create a GitHub App **or** a fine-grained PAT (`administration: write` on `SweptLock/sweptlock-engine`).
- Add a repo **webhook** for `workflow_job` events → the dispatcher URL (Phase 3 gives the URL + secret).
- Store the App key / PAT + webhook secret in Secret Manager (I'll script the gcloud).

## Cost
Idle: **$0**. Per build: ~build-minutes × (8 vCPU/32 GB), per-second billing — a few cents
to ~$0.50/build. The image lives in Artifact Registry (small monthly storage cost).
