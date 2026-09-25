# ---------------------------------------------------------------------------
# GitHub Actions OIDC — the identity side of CI's access to AWS.
#
# This module creates the aws_iam_openid_connect_provider for GitHub Actions
# and the two IAM roles CI assumes (plan, apply). It does NOT create the
# state-access permissions those roles end up with — that's
# terraform/modules/account-foundation, which accepts these roles' ARNs as
# plan_role_trusted_principal_arns / apply_role_trusted_principal_arns.
#
# Split into two modules deliberately: this one owns "who is GitHub Actions,
# as far as AWS IAM is concerned" (identity), account-foundation owns "what
# can the Terraform state backend's plan/apply roles actually do" (state
# access permissions). Neither module needs to know the other exists beyond
# passing an ARN across the boundary.
# ---------------------------------------------------------------------------

locals {
  # thumbprint_list is deliberately omitted below, not just left at a
  # default — AWS validates GitHub's OIDC endpoint against its own library
  # of trusted root CAs for GitHub specifically, not a thumbprint supplied
  # here. See https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html
  github_oidc_url = "https://token.actions.githubusercontent.com"

  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.existing_oidc_provider_arn

  # Default sub-claim conditions, only used if the caller didn't override
  # plan_role_ref_condition / apply_role_ref_condition. See GitHub's own
  # OIDC docs for the "repo:ORG/REPO:..." subject format:
  # https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services
  default_plan_ref_condition  = ["repo:${var.github_repository}:*"]
  default_apply_ref_condition = ["repo:${var.github_repository}:ref:refs/heads/main"]

  plan_role_ref_condition  = coalesce(var.plan_role_ref_condition, local.default_plan_ref_condition)
  apply_role_ref_condition = coalesce(var.apply_role_ref_condition, local.default_apply_ref_condition)
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url             = local.github_oidc_url
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [] # intentionally empty — see locals.github_oidc_url comment above

  tags = merge(var.tags, {
    Name = "github-actions-oidc"
  })
}

# --- plan role: assumable from any ref in the named repo, read-only by design ---

data "aws_iam_policy_document" "plan_role_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.plan_role_ref_condition
    }
  }
}

resource "aws_iam_role" "plan" {
  name               = var.plan_role_name
  assume_role_policy = data.aws_iam_policy_document.plan_role_assume.json
  tags               = var.tags
}

# --- apply role: main branch only, per apply_role_ref_condition's default ---

data "aws_iam_policy_document" "apply_role_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.apply_role_ref_condition
    }
  }
}

resource "aws_iam_role" "apply" {
  name               = var.apply_role_name
  assume_role_policy = data.aws_iam_policy_document.apply_role_assume.json
  tags               = var.tags
}
