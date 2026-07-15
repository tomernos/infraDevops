locals {
  # app_github_owner defaults to github_owner if not explicitly set
  app_owner = var.app_github_owner != "" ? var.app_github_owner : var.github_owner
}

# ── Workload Identity Federation Pool ────────────────────────────────────────

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "${var.name_prefix}-wif-pool"
  display_name              = "GitHub Actions"
  description               = "WIF pool for GitHub Actions — no JSON keys ever"
  project                   = var.project_id
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  display_name                       = "GitHub OIDC"
  project                            = var.project_id

  # Accept tokens from infra owner OR app owner (may be different GitHub users)
  attribute_condition = "assertion.repository_owner in ['${var.github_owner}', '${local.app_owner}']"

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.actor"            = "assertion.actor"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.ref"              = "assertion.ref"
  }

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# ── CI Service Accounts ───────────────────────────────────────────────────────

# Pushes images + deploys to VM (used by app repo workflows)
resource "google_service_account" "sa_ci_deploy" {
  account_id   = "${var.name_prefix}-sa-ci-deploy"
  display_name = "CI Deploy"
  description  = "Used by GitHub Actions to push images and deploy to the VM"
  project      = var.project_id
}

# Runs terragrunt plan on PRs (read-only, used by infra repo)
resource "google_service_account" "sa_ci_tf_plan" {
  account_id   = "${var.name_prefix}-sa-ci-tf-plan"
  display_name = "CI Terraform Plan"
  description  = "Read-only SA for terraform plan on infra PRs"
  project      = var.project_id
}

# Runs terragrunt apply on merge to main (used by infra repo)
resource "google_service_account" "sa_ci_tf_apply" {
  account_id   = "${var.name_prefix}-sa-tf-apply"
  display_name = "CI Terraform Apply Sandbox"
  description  = "Apply SA for sandbox infrastructure changes"
  project      = var.project_id
}

# ── WIF Bindings — allow each repo to impersonate its SA ─────────────────────

resource "google_service_account_iam_member" "ci_deploy_wif" {
  service_account_id = google_service_account.sa_ci_deploy.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${local.app_owner}/${var.app_repo}"
}

resource "google_service_account_iam_member" "ci_tf_plan_wif" {
  service_account_id = google_service_account.sa_ci_tf_plan.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_owner}/${var.infra_repo}"
}

resource "google_service_account_iam_member" "ci_tf_apply_wif" {
  service_account_id = google_service_account.sa_ci_tf_apply.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_owner}/${var.infra_repo}"
}

# ── IAM Roles — sa-ci-deploy ──────────────────────────────────────────────────

locals {
  deploy_roles = [
    "roles/artifactregistry.writer",    # push images
    "roles/compute.osLogin",            # SSH to VM via IAP
    "roles/iap.tunnelResourceAccessor", # open IAP tunnel
    "roles/compute.viewer",             # describe instances (get IP, zone)
  ]
}

resource "google_project_iam_member" "ci_deploy_roles" {
  for_each = toset(local.deploy_roles)
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.sa_ci_deploy.email}"
}

# Needed so ci-deploy can SSH to VMs that run as sa-api
resource "google_service_account_iam_member" "ci_deploy_sa_user" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${var.sa_api_email}"
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.sa_ci_deploy.email}"
}

# ── IAM Roles — sa-ci-tf-plan (read-only) ────────────────────────────────────

resource "google_project_iam_member" "ci_tf_plan_viewer" {
  project = var.project_id
  role    = "roles/viewer"
  member  = "serviceAccount:${google_service_account.sa_ci_tf_plan.email}"
}

resource "google_storage_bucket_iam_member" "ci_tf_plan_state_reader" {
  bucket = var.state_bucket
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.sa_ci_tf_plan.email}"
}

# Refreshing IAM-member resources (e.g. google_storage_bucket_iam_member on the guest-sharing
# quarantine bucket) calls *.getIamPolicy, which roles/viewer lacks for GCS buckets. securityReviewer
# is the read-only union of *.getIamPolicy across services — get, never set — so the plan SA can
# refresh any IAM binding without gaining a mutate permission.
resource "google_project_iam_member" "ci_tf_plan_security_reviewer" {
  project = var.project_id
  role    = "roles/iam.securityReviewer"
  member  = "serviceAccount:${google_service_account.sa_ci_tf_plan.email}"
}

# ── IAM Roles — sa-ci-tf-apply-sandbox ───────────────────────────────────────
# Editor covers all resource creation in sandbox. Tighten per-role in prod.

resource "google_project_iam_member" "ci_tf_apply_editor" {
  project = var.project_id
  role    = "roles/editor"
  member  = "serviceAccount:${google_service_account.sa_ci_tf_apply.email}"
}

resource "google_storage_bucket_iam_member" "ci_tf_apply_state_admin" {
  bucket = var.state_bucket
  role   = "roles/storage.admin"
  member = "serviceAccount:${google_service_account.sa_ci_tf_apply.email}"
}

# apply also needs to manage IAM (editor doesn't include this)
resource "google_project_iam_member" "ci_tf_apply_iam_admin" {
  project = var.project_id
  role    = "roles/resourcemanager.projectIamAdmin"
  member  = "serviceAccount:${google_service_account.sa_ci_tf_apply.email}"
}

# roles/editor excludes pubsub *.getIamPolicy/*.setIamPolicy, and projectIamAdmin only covers
# project-level IAM — neither lets apply refresh/manage resource-level pubsub IAM. The activity-log
# module's google_pubsub_topic_iam_member / google_pubsub_subscription_iam_member resources call
# topics/subscriptions getIamPolicy on every plan, which 403s without this. pubsub.admin is the
# scoped role covering get+set on both. (Mirrors the plan SA's securityReviewer fix in #19.)
resource "google_project_iam_member" "ci_tf_apply_pubsub_admin" {
  project = var.project_id
  role    = "roles/pubsub.admin"
  member  = "serviceAccount:${google_service_account.sa_ci_tf_apply.email}"
}
