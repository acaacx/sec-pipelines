#!/usr/bin/env bash
# Gate 3 — SAST via Semgrep. Args: <target-dir> <name>. --error => exit 1 on
# any blocking finding.
#   scan-sast.sh app-python python
#   scan-sast.sh app-java   java
set -euo pipefail
source "$(dirname "$0")/lib.sh"

target="${1:?usage: scan-sast.sh <target-dir> <name>}"
name="${2:?usage: scan-sast.sh <target-dir> <name>}"

# Language-specific ruleset in addition to the shared OWASP + secrets packs.
case "$name" in
  python) lang_config="p/python" ;;
  java)   lang_config="p/java" ;;
  *)      lang_config="p/default" ;;
esac

log "Semgrep: scanning ${target} (${name})"
semgrep scan "$REPO_ROOT/$target" \
  --config "$lang_config" \
  --config p/owasp-top-ten \
  --config p/secrets \
  --sarif --output "$REPO_ROOT/semgrep-${name}.sarif" \
  --error
