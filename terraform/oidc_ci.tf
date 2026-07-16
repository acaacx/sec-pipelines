# =============================================================================
# Additional OIDC federation for GitLab CI and Jenkins.
#
# The pipeline logic is portable (shared ./scripts), but each CI platform is a
# DIFFERENT OIDC issuer with a DIFFERENT subject claim, so each needs its own
# AWS IAM OIDC provider + trust policy and its own Entra federated credential.
#
# Guarded by feature flags — enable only the platforms you actually run.
# Reuses data.aws_iam_policy_document.deploy_permissions and
# azuread_application.github from oidc_setup.tf.
# =============================================================================

# -----------------------------------------------------------------------------
# Feature flags + platform coordinates
# -----------------------------------------------------------------------------
variable "enable_gitlab" {
  description = "Provision GitLab CI OIDC federation."
  type        = bool
  default     = false
}

variable "gitlab_issuer" {
  description = "GitLab OIDC issuer (https://gitlab.com or self-managed URL)."
  type        = string
  default     = "https://gitlab.com"
}

variable "gitlab_project_path" {
  description = "GitLab project path, e.g. mygroup/sec-pipelines."
  type        = string
  default     = ""
}

variable "enable_jenkins" {
  description = "Provision Jenkins OIDC federation."
  type        = bool
  default     = false
}

variable "jenkins_issuer" {
  description = "Jenkins OIDC issuer URL (from the OpenID Connect Provider plugin)."
  type        = string
  default     = ""
}

variable "jenkins_subject" {
  description = "Exact subject claim Jenkins issues for pipeline id tokens."
  type        = string
  default     = ""
}

# =============================================================================
# GitLab — AWS IAM OIDC provider + per-environment deploy roles
# =============================================================================
data "tls_certificate" "gitlab" {
  count = var.enable_gitlab ? 1 : 0
  url   = var.gitlab_issuer
}

resource "aws_iam_openid_connect_provider" "gitlab" {
  count           = var.enable_gitlab ? 1 : 0
  url             = var.gitlab_issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = data.tls_certificate.gitlab[0].certificates[*].sha1_fingerprint
}

locals {
  gitlab_host = var.enable_gitlab ? replace(var.gitlab_issuer, "https://", "") : ""
}

data "aws_iam_policy_document" "gitlab_trust" {
  for_each = var.enable_gitlab ? local.env_subjects : {}

  statement {
    sid     = "GitLabCIOIDC"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.gitlab[0].arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.gitlab_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Restrict to this project ...
    condition {
      test     = "StringLike"
      variable = "${local.gitlab_host}:sub"
      values   = ["project_path:${var.gitlab_project_path}:*"]
    }

    # ... AND to the matching GitLab environment (mirrors GHA env scoping).
    condition {
      test     = "StringEquals"
      variable = "${local.gitlab_host}:environment"
      values   = [each.key]
    }
  }
}

resource "aws_iam_role" "gitlab_deploy" {
  for_each             = var.enable_gitlab ? local.env_subjects : {}
  name                 = "gitlab-${var.github_repo}-deploy-${each.key}"
  assume_role_policy   = data.aws_iam_policy_document.gitlab_trust[each.key].json
  max_session_duration = 3600

  tags = {
    ManagedBy   = "terraform"
    Purpose     = "gitlab-ci-oidc"
    Environment = each.key
  }
}

resource "aws_iam_role_policy" "gitlab_deploy" {
  for_each = aws_iam_role.gitlab_deploy
  name     = "deploy-permissions"
  role     = each.value.id
  policy   = data.aws_iam_policy_document.deploy_permissions.json
}

# GitLab — Entra federated credentials (per environment) on the shared app.
resource "azuread_application_federated_identity_credential" "gitlab_env" {
  for_each = var.enable_gitlab ? local.env_subjects : {}

  application_id = azuread_application.github.id
  display_name   = "gitlab-${var.github_repo}-${each.key}"
  description    = "GitLab CI OIDC — ${var.gitlab_project_path}, environment ${each.key}"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = var.gitlab_issuer
  # GitLab id-token subject for an environment-scoped job.
  subject = "project_path:${var.gitlab_project_path}:environment:${each.key}"
}

# =============================================================================
# Jenkins — AWS IAM OIDC provider + single deploy role
# =============================================================================
data "tls_certificate" "jenkins" {
  count = var.enable_jenkins ? 1 : 0
  url   = var.jenkins_issuer
}

resource "aws_iam_openid_connect_provider" "jenkins" {
  count           = var.enable_jenkins ? 1 : 0
  url             = var.jenkins_issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = data.tls_certificate.jenkins[0].certificates[*].sha1_fingerprint
}

locals {
  jenkins_host = var.enable_jenkins ? replace(var.jenkins_issuer, "https://", "") : ""
}

data "aws_iam_policy_document" "jenkins_trust" {
  count = var.enable_jenkins ? 1 : 0

  statement {
    sid     = "JenkinsOIDC"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.jenkins[0].arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.jenkins_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.jenkins_host}:sub"
      values   = [var.jenkins_subject]
    }
  }
}

resource "aws_iam_role" "jenkins_deploy" {
  count                = var.enable_jenkins ? 1 : 0
  name                 = "jenkins-${var.github_repo}-deploy"
  assume_role_policy   = data.aws_iam_policy_document.jenkins_trust[0].json
  max_session_duration = 3600

  tags = {
    ManagedBy = "terraform"
    Purpose   = "jenkins-oidc"
  }
}

resource "aws_iam_role_policy" "jenkins_deploy" {
  count  = var.enable_jenkins ? 1 : 0
  name   = "deploy-permissions"
  role   = aws_iam_role.jenkins_deploy[0].id
  policy = data.aws_iam_policy_document.deploy_permissions.json
}

# Jenkins — Entra federated credential on the shared app.
resource "azuread_application_federated_identity_credential" "jenkins" {
  count = var.enable_jenkins ? 1 : 0

  application_id = azuread_application.github.id
  display_name   = "jenkins-${var.github_repo}"
  description    = "Jenkins OIDC — ${var.jenkins_subject}"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = var.jenkins_issuer
  subject        = var.jenkins_subject
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "gitlab_role_arns" {
  description = "GitLab per-environment deploy role ARNs."
  value       = { for env, role in aws_iam_role.gitlab_deploy : env => role.arn }
}

output "jenkins_role_arn" {
  description = "Jenkins deploy role ARN."
  value       = var.enable_jenkins ? aws_iam_role.jenkins_deploy[0].arn : null
}
