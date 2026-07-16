#!/usr/bin/env bash
# Exchange a CI-issued OIDC JWT for short-lived AWS credentials via STS
# AssumeRoleWithWebIdentity. No long-lived keys. Prints `export` lines on
# stdout; caller does:  eval "$(scripts/aws-oidc-login.sh)"
#
# Required env:
#   AWS_ROLE_ARN   target IAM role
#   AWS_OIDC_TOKEN the OIDC JWT (GitLab id_tokens / Jenkins OIDC plugin)
#   AWS_REGION     region (default eu-west-1)
set -euo pipefail
source "$(dirname "$0")/lib.sh"

: "${AWS_ROLE_ARN:?AWS_ROLE_ARN required}"
: "${AWS_OIDC_TOKEN:?AWS_OIDC_TOKEN required}"
export AWS_DEFAULT_REGION="${AWS_REGION:-eu-west-1}"
session="${OIDC_SESSION_NAME:-ci-$(date +%s)}"

read -r ak sk st < <(
  aws sts assume-role-with-web-identity \
    --role-arn "$AWS_ROLE_ARN" \
    --role-session-name "$session" \
    --web-identity-token "$AWS_OIDC_TOKEN" \
    --duration-seconds 3600 \
    --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
    --output text
)
[ -n "$ak" ] || die "STS returned no credentials"

log "assumed ${AWS_ROLE_ARN} (session ${session})"
echo "export AWS_ACCESS_KEY_ID=${ak}"
echo "export AWS_SECRET_ACCESS_KEY=${sk}"
echo "export AWS_SESSION_TOKEN=${st}"
echo "export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION}"
