#!/usr/bin/env bash
# Gate 2 — IaC scanning. soft-fail is false in .checkov.yaml, so a failed
# policy check exits non-zero. SARIF emitted for upload to the security UI.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log "Checkov: scanning Terraform + GitHub Actions"
checkov \
  --config-file "$REPO_ROOT/.checkov.yaml" \
  --output cli \
  --output sarif \
  --output-file-path "console,${REPO_ROOT}"
# Writes ${REPO_ROOT}/results_sarif.sarif ; exit code non-zero on failed checks.
