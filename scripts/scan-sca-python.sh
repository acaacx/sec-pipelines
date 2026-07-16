#!/usr/bin/env bash
# Gate 4a — Python SCA. Any known vuln or unresolvable dep => exit 1.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log "pip-audit: scanning app-python/requirements.txt"
pip-audit \
  --requirement "$REPO_ROOT/app-python/requirements.txt" \
  --strict \
  --desc
