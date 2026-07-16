#!/usr/bin/env bash
# Log in to Azure using a CI-issued OIDC JWT as a federated credential.
# No client secret. Required env:
#   AZURE_CLIENT_ID  AZURE_TENANT_ID  AZURE_SUBSCRIPTION_ID  AZURE_OIDC_TOKEN
set -euo pipefail
source "$(dirname "$0")/lib.sh"

: "${AZURE_CLIENT_ID:?}"; : "${AZURE_TENANT_ID:?}"
: "${AZURE_SUBSCRIPTION_ID:?}"; : "${AZURE_OIDC_TOKEN:?}"

log "az login (federated OIDC, no secret)"
az login --service-principal \
  --username "$AZURE_CLIENT_ID" \
  --tenant "$AZURE_TENANT_ID" \
  --federated-token "$AZURE_OIDC_TOKEN" \
  --output none
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
