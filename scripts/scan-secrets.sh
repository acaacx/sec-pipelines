#!/usr/bin/env bash
# Gate 1 — secrets detection over full git history. Any finding => exit 1.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log "Gitleaks: scanning full git history"
gitleaks detect \
  --source "$REPO_ROOT" \
  --config "$REPO_ROOT/.gitleaks.toml" \
  --redact \
  --report-format sarif \
  --report-path "$REPO_ROOT/gitleaks.sarif" \
  --exit-code 1
