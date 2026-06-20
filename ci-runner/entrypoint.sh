#!/usr/bin/env bash
#
# Ephemeral runner entrypoint.
#
# The dispatcher (Phase 3) mints a JIT (just-in-time) runner config from the GitHub
# API and passes it to this Cloud Run Job execution as the JITCONFIG env var. A JIT
# config is single-use and implies an EPHEMERAL runner: it registers, GitHub assigns
# it exactly one queued job, it runs, then it deregisters and this process exits —
# so the Cloud Run Job task completes and we scale back to zero. No long-lived tokens.
set -euo pipefail

if [[ -z "${JITCONFIG:-}" ]]; then
  echo "FATAL: JITCONFIG is empty. The dispatcher must pass a one-time JIT runner config." >&2
  exit 1
fi

cd /home/runner

# --jitconfig registers + runs one job + exits. No config.sh/remove needed.
exec ./run.sh --jitconfig "${JITCONFIG}"
