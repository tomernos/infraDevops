# `shared` — central CI runner project (`sweptlock-shared`)

Not an application environment. This project holds **CI compute only**: an Artifact Registry for
runner images and one Cloud Run Job that hosts a self-hosted GitHub Actions runner.

Why it exists: jobs that run on a self-hosted runner **do not consume GitHub Actions minutes**. With
the org's hosted budget exhausted, moving pipelines onto self-hosted compute is the practical
unblock — and centralizing that compute in one project beats standing a runner up inside dev, prod,
and every future project.

Design + decision record:
`ReferencesContext/sweptlock/plans/shared-runner-project-design.md`

## The load-bearing principle: two identities, not one

| | Runner (compute) | Deploy SA (credentials) |
|---|---|---|
| What | where the pipeline process runs | the identity that actually deploys |
| Power | **none** — `sa-runner` holds zero GCP roles | least-privilege, per-env |
| How it gets power | it doesn't | GitHub OIDC → WIF → impersonation, per job |
| Location | centralized **here** | **stays in the target project** |

Because deploy power is WIF-federated per job rather than attached to the runner, moving the runner
needs almost no new cross-project IAM, and this project is granted no authority over dev or prod.
The one cross-project binding is `sa-eng-deploy` (dev) → `actAs` on `sa-runner` (here).

## Units

| Unit | What |
|---|---|
| `registry` | `swpt-mw1-shared-registry` — runner images only. Grants the DEV engine deploy SA repo-scoped **writer** so `build-runner-image.yml` can push here. |
| `ci-runner` | `sa-runner` (zero roles) + the cross-project actAs binding + Cloud Run Job `swpt-mw1-shared-runner` in **persistent** mode. |

## Bring-up (once)

> **⚠️ Order matters: the runner image must exist BEFORE the `ci-runner` apply.** Creating a Cloud Run
> Job validates that its image is pullable and fails with `Error code 5 … Image not found` otherwise —
> the Job is then left tainted in state, so the retry is a plain `terragrunt apply` (it replaces it;
> `deletion_protection = false` allows that). This is why `run --all` is split below.

```bash
# 1. project + billing (done manually)
# 2. bootstrap: state bucket, lean API set, WIF pool, tf plan/apply SAs
./scripts/bootstrap.sh shared

# 3. registry FIRST — the image needs somewhere to land
cd regions/me-west1/shared/registry && terragrunt apply

# 4. publish the runner image (see "Publishing the runner image" below)

# 5. now the Job can be created
cd ../ci-runner && terragrunt apply
```

Applying locally as Owner uses the `GOOGLE_OAUTH_ACCESS_TOKEN` pattern:
`export GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token)` covers both the google provider
and the GCS backend.

For CI to manage this env, add from `bootstrap.sh`'s output:

- repo secrets `WIF_PROVIDER_SHARED`, `SA_CI_TF_PLAN_EMAIL_SHARED`
- a GitHub Environment named `shared` with secret `SA_CI_TF_APPLY_EMAIL`

Without them `_tf-core.yml` fails closed — it never falls back to dev credentials.

**Status: LIVE and PROVEN (2026-07-30).** Registry + `sa-runner` + cross-project actAs + the runner
Job are all applied; the image is published; the runner registered as `cloudrun-shared` with labels
`[self-hosted, Linux, X64, cloudrun]`; and a full dev backend deploy ran end-to-end on it — run
`30534743368`, all five jobs (`preflight → build → approve → migrate → deploy`) on `cloudrun-shared`,
zero hosted Actions minutes, live revision `swpt-mw1-dev-api-00045-tb4`, `/health` and `/health/ready`
both 200. Afterwards the execution was cancelled and dev Cloud SQL returned to `NEVER`.

> **⚠️ Bootstrap caveat, observed 2026-07-30 (since RESOLVED by a re-run).** The first
> `bootstrap.sh shared` run stopped part-way:
> the state bucket, API set, WIF pool and both SAs were created, and the **plan** SA got
> `viewer` + `iam.securityReviewer` — but the **apply** SA (`swpt-mw1-shared-sa-tf-apply`) ended with
> **zero** project bindings and no `storage.admin` on the state bucket. Local Owner applies hide this
> (they don't use that SA), so it only bites the first CI-driven apply. The script is idempotent —
> re-run `./scripts/bootstrap.sh shared` and then VERIFY, don't assume:
> ```bash
> gcloud projects get-iam-policy sweptlock-shared --flatten="bindings[].members" \
>   --format="table(bindings.members,bindings.role)" | grep tf-apply   # expect editor + 4 more
> gsutil iam get gs://swpt-mw1-infra-shared-tf | grep -A2 tf-apply     # expect storage.admin
> ```

## Publishing the runner image

Normally `build-runner-image.yml` (sweptlock-engine) does this. It needs `docker buildx`, so it can
only run on a **github-hosted** runner — under an exhausted Actions budget, publish out-of-band.

**Cloud Build (server-side; no multi-GB local transfer). This exact command is PROVEN — build
`f8488750`, 2026-07-30.** It runs in the **dev** project as the dev engine deploy SA and pushes into
this registry, which is the same identity and direction `build-runner-image.yml` uses — so it also
validates the `extra_writer_sa_emails` grant.

```bash
cd <engine>/infra/runner
gcloud builds submit . \
  --project=sweptlock-dev-844f2 \
  --service-account=projects/sweptlock-dev-844f2/serviceAccounts/swpt-mw1-dev-sa-eng-deploy@sweptlock-dev-844f2.iam.gserviceaccount.com \
  --gcs-source-staging-dir=gs://sweptlock-dev-844f2_cloudbuild/source \
  --gcs-log-dir=gs://sweptlock-dev-844f2_cloudbuild/logs \
  --timeout=1800 --async \
  --tag me-west1-docker.pkg.dev/sweptlock-shared/swpt-mw1-shared-registry/runner:latest
```

Takes ~8 min (it downloads the Android SDK + NDK). Poll with
`gcloud builds describe <id> --project=sweptlock-dev-844f2 --format='value(status)'`.

> **Why not a plain `gcloud builds submit` in this project?** Tried, and it fails:
> ```
> INVALID_ARGUMENT: could not resolve source: … 1090308823904-compute@developer.gserviceaccount.com
> does not have storage.objects.get access to … sweptlock-shared_cloudbuild/objects/source/…
> ```
> Cloud Build defaults the build to the **Compute Engine default SA**, which is role-stripped org-wide.
> The presence of the legacy `<projectnumber>@cloudbuild.gserviceaccount.com` with
> `roles/cloudbuild.builds.builder` does **not** make it the default — don't be fooled by finding it in
> the IAM policy. If you do want to build in-project, pass `--service-account=<an SA that can write>`
> **plus** `--default-buckets-behavior=regional-user-owned-bucket` (naming a build SA makes the default
> logs bucket unusable). Note `PERMISSION_DENIED: The caller does not have permission` while you are
> Owner and `builds list` works = the BUILD identity is wrong, not yours.

**Fallback — retag the image that already exists in dev** (certain, but pulls/pushes several GB
through your machine; Docker Desktop is Windows-side, so run it from PowerShell):

```powershell
gcloud auth configure-docker me-west1-docker.pkg.dev
docker pull me-west1-docker.pkg.dev/sweptlock-dev-844f2/swpt-mw1-dev-registry/runner:latest
docker tag  me-west1-docker.pkg.dev/sweptlock-dev-844f2/swpt-mw1-dev-registry/runner:latest `
            me-west1-docker.pkg.dev/sweptlock-shared/swpt-mw1-shared-registry/runner:latest
docker push me-west1-docker.pkg.dev/sweptlock-shared/swpt-mw1-shared-registry/runner:latest
```

## Starting the runner (each time hosted minutes are unavailable)

```bash
# 1. route the deploy workflows to self-hosted
gh variable set RUNNER_PREFERENCE --body self-hosted --repo SweptLock/sweptlock-engine

# 2. mint a 1h registration token and launch the runner with it
TOK=$(gh api -X POST repos/SweptLock/sweptlock-engine/actions/runners/registration-token --jq .token)
gcloud run jobs execute swpt-mw1-shared-runner \
  --region me-west1 --project sweptlock-shared \
  --update-env-vars RUNNER_REG_TOKEN=$TOK

# 3. dispatch the deploy workflows — they land on label `cloudrun`
# 4. when done: flip RUNNER_PREFERENCE back to `hosted` and cancel the execution
gh variable set RUNNER_PREFERENCE --body hosted --repo SweptLock/sweptlock-engine
```

The token is **never stored in Terraform** — the Job holds a placeholder that the bootstrap script
refuses to run with, and the real token arrives as a per-execution env override. The 6h
`task_timeout` is a deliberate dead-man's switch: a forgotten runner is both idle spend and a
long-lived box trusted by CI.

**Registration scope.** The stored `runner_url` is the **engine** repo (the proven configuration), so
one execution serves engine jobs. Override `RUNNER_URL` in the same `--update-env-vars` to register
elsewhere without an apply:

- infra jobs → `https://github.com/SweptLock/Sweptlock-Infra` + an infra registration token
- all repos at once → `https://github.com/SweptLock` + an **org** registration token
  (`gh api -X POST orgs/SweptLock/actions/runners/registration-token`), which is where this is headed

## Deliberately not here

No SQL, VPC, KMS, Secret Manager, Cloud Run service, or app data — see `env.hcl`. Adding any of
those means this project stopped being CI compute and needs its own security review first.
