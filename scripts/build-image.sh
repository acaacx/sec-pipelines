#!/usr/bin/env bash
# Build an application image LOCALLY (never pushed here). Args: <app-dir>.
# Prints the local image ref on stdout for the caller to feed into Trivy.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

app="${1:?usage: build-image.sh <app-dir>}"
tag="${IMAGE_TAG:-$(git -C "$REPO_ROOT" rev-parse HEAD)}"
ref="${app}:${tag}"

log "docker build ${ref} (local only)"
docker build -t "$ref" "$REPO_ROOT/$app" >&2
echo "$ref"
