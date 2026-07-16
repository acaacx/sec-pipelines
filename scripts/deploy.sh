#!/usr/bin/env bash
# Terraform deploy for one environment. Assumes AWS + Azure OIDC auth already
# established. Args: <environment>  (staging | production).
set -euo pipefail
source "$(dirname "$0")/lib.sh"

env="${1:?usage: deploy.sh <environment>}"
cd "$REPO_ROOT/terraform"

export ARM_USE_OIDC="true"
export ARM_CLIENT_ID="${AZURE_CLIENT_ID:?}"
export ARM_TENANT_ID="${AZURE_TENANT_ID:?}"
export ARM_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:?}"

log "terraform apply (${env})"
terraform init -backend-config="key=${env}/terraform.tfstate"
terraform fmt -check -recursive
terraform validate
terraform plan -var-file="environments/${env}.tfvars" -out=tfplan
terraform apply -auto-approve tfplan
