#!/usr/bin/env bash
# Tag and push a locally-built (and already-scanned) image to both ECR and ACR.
# Assumes AWS + Azure auth already established (OIDC). Args: <app-dir> <local-ref>.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

app="${1:?usage: push-image.sh <app-dir> <local-ref>}"
local_ref="${2:?usage: push-image.sh <app-dir> <local-ref>}"
tag="${IMAGE_TAG:-$(git -C "$REPO_ROOT" rev-parse HEAD)}"

: "${ECR_REPOSITORY:?}"; : "${AWS_REGION:?}"; : "${ACR_NAME:?}"

# ECR login + push
ecr_registry="$(aws ecr get-authorization-token \
  --query 'authorizationData[0].proxyEndpoint' --output text | sed 's#https://##')"
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ecr_registry"
ecr_ref="${ecr_registry}/${ECR_REPOSITORY}-${app}:${tag}"

# ACR login + push
az acr login --name "$ACR_NAME"
acr_ref="${ACR_NAME}.azurecr.io/${ECR_REPOSITORY}-${app}:${tag}"

for target in "$ecr_ref" "$acr_ref"; do
  log "push ${target}"
  docker tag "$local_ref" "$target"
  docker push "$target"
done
