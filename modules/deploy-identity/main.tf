# ── Reusable CI deploy identity (leaf) ───────────────────────────────────────
# One GitHub-Actions deploy service account + least-privilege roles + one repo-scoped Workload
# Identity binding. This module holds NO product knowledge: the component slug, GitHub repo,
# roles, actAs targets, and descriptions are all inputs from the Terragrunt live unit that
# instantiates it (one live unit per deployable component → per-component state boundary).
#
# The WIF pool + provider are auth plumbing Terraform authenticates *through*, so they are NOT
# managed here (they live in scripts/bootstrap.sh). This module only derives the pool's full
# resource name — from the project number + a conventional pool id — to build the principalSet.

data "google_project" "this" {
  project_id = var.project_id
}

locals {
  pool_id   = var.wif_pool_id != "" ? var.wif_pool_id : "${var.name_prefix}-wif-pool"
  pool_name = "projects/${data.google_project.this.number}/locations/global/workloadIdentityPools/${local.pool_id}"
}

resource "google_service_account" "this" {
  account_id   = "${var.name_prefix}-sa-${var.component}-deploy"
  display_name = var.display_name
  description  = var.description
  project      = var.project_id
}

# Project-level roles the deploy workflow needs (e.g. artifactregistry.writer, run.developer).
resource "google_project_iam_member" "roles" {
  for_each = toset(var.project_roles)
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.this.email}"
}

# actAs on each runtime SA — required so a Cloud Run deploy can create revisions that RUN AS
# that runtime SA. Without this, `gcloud run deploy --service-account=<runtime>` is denied.
resource "google_service_account_iam_member" "act_as" {
  for_each           = toset(var.act_as_service_accounts)
  service_account_id = "projects/${var.project_id}/serviceAccounts/${each.value}"
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.this.email}"
}

# Repo-scoped federation: only this exact GitHub repo may mint tokens that impersonate this SA.
resource "google_service_account_iam_member" "wif" {
  service_account_id = google_service_account.this.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${local.pool_name}/attribute.repository/${var.github_repo}"
}

# actAs on ITSELF — only when the workflow runs Cloud Build AS this deploy SA (see var.act_as_self).
# Additive member (never authoritative), so it cannot remove any other actAs principal on the SA.
resource "google_service_account_iam_member" "act_as_self" {
  count              = var.act_as_self ? 1 : 0
  service_account_id = google_service_account.this.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.this.email}"
}

# Bucket-scoped grants (e.g. the Cloud Build `<project>_cloudbuild` source-staging bucket). Additive
# per (bucket, role) member — leaves every other bucket principal untouched.
resource "google_storage_bucket_iam_member" "bucket" {
  for_each = { for b in var.bucket_iam : "${b.bucket}:${b.role}" => b }
  bucket   = each.value.bucket
  role     = each.value.role
  member   = "serviceAccount:${google_service_account.this.email}"
}
