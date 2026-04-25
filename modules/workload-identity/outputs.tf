output "wif_provider" {
  description = "Full WIF provider resource name — paste into GitHub Actions as WIF_PROVIDER secret"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "sa_ci_deploy_email" {
  description = "SA email for app repo deploy workflows — paste as SA_CI_DEPLOY_EMAIL secret"
  value       = google_service_account.sa_ci_deploy.email
}

output "sa_ci_tf_plan_email" {
  description = "SA email for infra repo plan workflow — paste as SA_CI_TF_PLAN_EMAIL secret"
  value       = google_service_account.sa_ci_tf_plan.email
}

output "sa_ci_tf_apply_email" {
  description = "SA email for infra repo apply workflow — paste as SA_CI_TF_APPLY_EMAIL secret"
  value       = google_service_account.sa_ci_tf_apply.email
}
