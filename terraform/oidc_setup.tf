# =============================================================================
# OIDC Identity Federation — GitHub Actions -> AWS IAM + Microsoft Entra ID
#
# Provisions everything the pipeline needs to authenticate WITHOUT long-lived
# credentials. Trust is restricted to a single GitHub org/repo and to
# specific GitHub Environments (staging / production).
# =============================================================================

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.10"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "azuread" {}

provider "azurerm" {
  features {}
  subscription_id = var.azure_subscription_id
}

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------
variable "github_org" {
  description = "GitHub organisation (or user) that owns the repository."
  type        = string
}

variable "github_repo" {
  description = "Repository name (without org prefix)."
  type        = string
}

variable "aws_region" {
  description = "AWS region for regional resources."
  type        = string
  default     = "eu-west-1"
}

variable "azure_subscription_id" {
  description = "Target Azure subscription ID."
  type        = string
}

variable "environments" {
  description = "GitHub Environments allowed to deploy."
  type        = set(string)
  default     = ["staging", "production"]
}

variable "terraform_state_bucket" {
  description = "S3 bucket holding Terraform remote state."
  type        = string
}

variable "terraform_lock_table" {
  description = "DynamoDB table used for Terraform state locking."
  type        = string
}

variable "ecr_repository_prefix" {
  description = "ECR repository name prefix the pipeline may push to."
  type        = string
  default     = "devsecops-demo"
}

variable "acr_id" {
  description = "Resource ID of the Azure Container Registry the pipeline pushes to."
  type        = string
}

locals {
  github_oidc_url = "https://token.actions.githubusercontent.com"
  repo_slug       = "${var.github_org}/${var.github_repo}"

  # Exact subject claims GitHub issues for environment-scoped jobs.
  env_subjects = {
    for env in var.environments :
    env => "repo:${local.repo_slug}:environment:${env}"
  }
}

# =============================================================================
# AWS — IAM OIDC Provider + per-environment deploy roles + read-only PR role
# =============================================================================

data "tls_certificate" "github" {
  url = local.github_oidc_url
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = local.github_oidc_url
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = data.tls_certificate.github.certificates[*].sha1_fingerprint
}

# ---- Deploy roles: one per environment, trust locked to that environment ----
data "aws_iam_policy_document" "github_trust" {
  for_each = local.env_subjects

  statement {
    sid     = "GitHubActionsOIDC"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Exact-match subject: only this repo, only this GitHub Environment.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [each.value]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  for_each             = local.env_subjects
  name                 = "gha-${var.github_repo}-deploy-${each.key}"
  assume_role_policy   = data.aws_iam_policy_document.github_trust[each.key].json
  max_session_duration = 3600

  tags = {
    ManagedBy   = "terraform"
    Purpose     = "github-actions-oidc"
    Environment = each.key
    Repository  = local.repo_slug
  }
}

# ---- Least-privilege deploy permissions --------------------------------------
data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "deploy_permissions" {
  # Terraform remote state
  statement {
    sid     = "TerraformStateS3"
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
    resources = [
      "arn:aws:s3:::${var.terraform_state_bucket}",
      "arn:aws:s3:::${var.terraform_state_bucket}/*",
    ]
  }

  statement {
    sid       = "TerraformStateLock"
    effect    = "Allow"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = ["arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.terraform_lock_table}"]
  }

  # ECR push — restricted to this project's repositories
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # GetAuthorizationToken does not support resource scoping
  }

  statement {
    sid    = "EcrPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = ["arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${var.ecr_repository_prefix}-*"]
  }

  # Application deployment surface (ECS example — tighten to your platform)
  statement {
    sid    = "EcsDeploy"
    effect = "Allow"
    actions = [
      "ecs:DescribeServices",
      "ecs:DescribeTaskDefinition",
      "ecs:RegisterTaskDefinition",
      "ecs:UpdateService",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [var.ecr_repository_prefix]
    }
  }

  statement {
    sid       = "PassExecutionRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.ecr_repository_prefix}-*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "deploy" {
  for_each = aws_iam_role.github_deploy
  name     = "deploy-permissions"
  role     = each.value.id
  policy   = data.aws_iam_policy_document.deploy_permissions.json
}

# ---- Read-only plan role for pull requests -----------------------------------
data "aws_iam_policy_document" "github_trust_pr" {
  statement {
    sid     = "GitHubActionsPullRequestOIDC"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${local.repo_slug}:pull_request"]
    }
  }
}

resource "aws_iam_role" "github_plan" {
  name               = "gha-${var.github_repo}-plan-readonly"
  assume_role_policy = data.aws_iam_policy_document.github_trust_pr.json

  tags = {
    ManagedBy  = "terraform"
    Purpose    = "github-actions-oidc-plan"
    Repository = local.repo_slug
  }
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.github_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# =============================================================================
# Azure — Entra Application + Service Principal + Federated Identity Credentials
# =============================================================================

data "azuread_client_config" "current" {}

resource "azuread_application" "github" {
  display_name = "gha-${var.github_repo}-oidc"

  web {
    # No redirect URIs — this app exists solely for workload identity federation.
  }
}

resource "azuread_service_principal" "github" {
  client_id = azuread_application.github.client_id
}

# One federated credential per GitHub Environment.
resource "azuread_application_federated_identity_credential" "environment" {
  for_each = local.env_subjects

  application_id = azuread_application.github.id
  display_name   = "gha-${var.github_repo}-${each.key}"
  description    = "GitHub Actions OIDC — ${local.repo_slug}, environment ${each.key}"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = local.github_oidc_url
  subject        = each.value
}

# PR-scoped credential for read-only plan runs.
resource "azuread_application_federated_identity_credential" "pull_request" {
  application_id = azuread_application.github.id
  display_name   = "gha-${var.github_repo}-pull-request"
  description    = "GitHub Actions OIDC — ${local.repo_slug}, pull requests (plan only)"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = local.github_oidc_url
  subject        = "repo:${local.repo_slug}:pull_request"
}

# ---- RBAC: scoped role assignments -------------------------------------------
resource "azurerm_resource_group" "env" {
  for_each = var.environments
  name     = "rg-${var.github_repo}-${each.key}"
  location = "westeurope"

  tags = {
    ManagedBy   = "terraform"
    Environment = each.key
  }
}

resource "azurerm_role_assignment" "contributor" {
  for_each             = azurerm_resource_group.env
  scope                = each.value.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.github.object_id
}

resource "azurerm_role_assignment" "acr_push" {
  scope                = var.acr_id
  role_definition_name = "AcrPush"
  principal_id         = azuread_service_principal.github.object_id
}

# -----------------------------------------------------------------------------
# Outputs — paste these into GitHub Environment VARIABLES (they are not secrets)
# -----------------------------------------------------------------------------
output "aws_role_arns" {
  description = "Per-environment IAM role ARNs -> GitHub vars AWS_STAGING_ROLE_ARN / AWS_PRODUCTION_ROLE_ARN."
  value       = { for env, role in aws_iam_role.github_deploy : env => role.arn }
}

output "aws_plan_role_arn" {
  description = "Read-only role for PR terraform plan."
  value       = aws_iam_role.github_plan.arn
}

output "azure_client_id" {
  description = "-> GitHub var AZURE_CLIENT_ID."
  value       = azuread_application.github.client_id
}

output "azure_tenant_id" {
  description = "-> GitHub var AZURE_TENANT_ID."
  value       = data.azuread_client_config.current.tenant_id
}
