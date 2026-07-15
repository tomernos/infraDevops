# ── Drop-Zone quarantine bucket — ownership moved to the guest-sharing stack ──────────────────
#
# The bucket `${name_prefix}-quarantine` was, for a period, declared in BOTH this security stack AND
# modules/guest-sharing (the real drop-zone owner: bucket + malware-scanner + Eventarc + object IAM).
# Two Terraform owners in two separate states meant every `run --all apply` had them overwrite each
# other's CORS `origin` list, so the bucket drifted forever — guest-sharing's origins kept winning and
# this stack re-planned the identical change on every run (never converging; bucket metageneration
# climbed into the double digits from the churn).
#
# Resolution: **guest-sharing is the SOLE owner.** This `removed` block drops the bucket from THIS
# stack's state WITHOUT deleting it (`destroy = false`) — a one-time, no-op-once-applied cleanup. The
# full CORS allowlist (including the firebaseapp.com origin whose absence broke uploads) now lives only
# in modules/guest-sharing. Do not re-add a `google_storage_bucket "quarantine"` resource here.
removed {
  from = google_storage_bucket.quarantine
  lifecycle {
    destroy = false
  }
}
