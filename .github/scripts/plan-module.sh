#!/usr/bin/env bash
# plan-module.sh <module>
# Plans a single Terragrunt stack and writes results to /tmp/plan-result-<module>.txt
# Result file format: line1=status, line2=adds, line3=changes, line4=destroys
set -euo pipefail

MODULE="${1:?Usage: plan-module.sh <module>}"
STACK_DIR="regions/me-west1/sandbox/$MODULE"
OUTPUT_FILE="/tmp/plan-output-$MODULE.txt"
RESULT_FILE="/tmp/plan-result-$MODULE.txt"

echo "::group::📋 $MODULE — terragrunt plan"

cd "$STACK_DIR"

PLAN_EXIT=0
terragrunt plan --terragrunt-non-interactive -no-color 2>&1 | tee "$OUTPUT_FILE" || PLAN_EXIT=$?

echo "::endgroup::"

# Exit 0 = no changes, exit 2 = changes to apply, exit 1 = error
if [ "$PLAN_EXIT" -eq 1 ]; then
  echo "❌ Error" > "$RESULT_FILE"
  echo "0" >> "$RESULT_FILE"
  echo "0" >> "$RESULT_FILE"
  echo "0" >> "$RESULT_FILE"
  exit 0  # Don't fail the step — let the summary job report it
fi

PLAN_LINE=$(grep -E "^Plan:|No changes\." "$OUTPUT_FILE" | tail -1 || echo "")

if [[ -z "$PLAN_LINE" ]] || [[ "$PLAN_LINE" == *"No changes"* ]]; then
  echo "✅ No changes" > "$RESULT_FILE"
  echo "0" >> "$RESULT_FILE"
  echo "0" >> "$RESULT_FILE"
  echo "0" >> "$RESULT_FILE"
else
  ADDS=$(echo "$PLAN_LINE"    | grep -oP '\d+(?= to add)'     | head -1 || echo "0")
  CHGS=$(echo "$PLAN_LINE"    | grep -oP '\d+(?= to change)'  | head -1 || echo "0")
  DEST=$(echo "$PLAN_LINE"    | grep -oP '\d+(?= to destroy)' | head -1 || echo "0")

  if [ "${DEST:-0}" -gt 0 ]; then
    STATUS="⚠️ Destroys"
  else
    STATUS="📋 Changes"
  fi

  echo "$STATUS" > "$RESULT_FILE"
  echo "${ADDS:-0}"  >> "$RESULT_FILE"
  echo "${CHGS:-0}"  >> "$RESULT_FILE"
  echo "${DEST:-0}"  >> "$RESULT_FILE"
fi
