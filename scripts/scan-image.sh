#!/usr/bin/env bash
# Gate 5 — image scan. Sits between build and push. HIGH/CRITICAL => exit 1,
# so a vulnerable image never reaches a registry. Args: <image-ref> <name>.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

image="${1:?usage: scan-image.sh <image-ref> <name>}"
name="${2:?usage: scan-image.sh <image-ref> <name>}"

log "Trivy: scanning ${image}"
trivy image \
  --severity CRITICAL,HIGH \
  --ignore-unfixed \
  --exit-code 1 \
  --format sarif \
  --output "$REPO_ROOT/trivy-${name}.sarif" \
  "$image"
