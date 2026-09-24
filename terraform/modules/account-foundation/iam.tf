# ---------------------------------------------------------------------------
# Terraform state access roles
#
# Three roles, three distinct scopes. No static AWS credentials anywhere —
# every role is assumed via OIDC (CI) or SSO (humans). See MASTERPLAN.md
# §1.1 for the full reasoning behind this split.
#
#   plan-role              read-only on state, lock-file write only
#   apply-role              full read/write on state + lock
#   developer-readonly       same scope as plan-role, for local debugging
#
# None of these grant terraform apply capability from a human's local
# machine, including administrators — apply only ever runs from the gated
# CI workflow that assumes apply-role.
# ---------------------------------------------------------------------------

locals {
  state_bucket_arn = aws_s3_bucket.state.arn
}

# --- plan-role ---------------------------------------------------------

data "aws_iam_policy_document" "plan_role_assume" {
  count = length(var.plan_role_trusted_principal_arns) > 0 ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = var.plan_role_trusted_principal_arns
    }
  }
}

resource "aws_iam_role" "plan" {
  count = length(var.plan_role_trusted_principal_arns) > 0 ? 1 : 0

  name               = "${var.account_name}-terraform-plan"
  assume_role_policy = data.aws_iam_policy_document.plan_role_assume[0].json
  tags               = var.tags
}

data "aws_iam_policy_document" "plan_role_permissions" {
  statement {
    sid    = "ReadState"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      local.state_bucket_arn,
      "${local.state_bucket_arn}/*",
    ]
  }

  statement {
    sid    = "WriteLockFileOnly"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [
      "${local.state_bucket_arn}/*.tflock",
    ]
  }

  statement {
    sid    = "DecryptStateWithKmsKey"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
    ]
    resources = [aws_kms_key.state.arn]
  }
}

resource "aws_iam_role_policy" "plan" {
  count = length(var.plan_role_trusted_principal_arns) > 0 ? 1 : 0

  name   = "state-read-lockfile-write"
  role   = aws_iam_role.plan[0].id
  policy = data.aws_iam_policy_document.plan_role_permissions.json
}

# --- apply-role ---------------------------------------------------------

data "aws_iam_policy_document" "apply_role_assume" {
  count = length(var.apply_role_trusted_principal_arns) > 0 ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = var.apply_role_trusted_principal_arns
    }
  }
}

resource "aws_iam_role" "apply" {
  count = length(var.apply_role_trusted_principal_arns) > 0 ? 1 : 0

  name               = "${var.account_name}-terraform-apply"
  assume_role_policy = data.aws_iam_policy_document.apply_role_assume[0].json
  tags               = var.tags
}

data "aws_iam_policy_document" "apply_role_permissions" {
  statement {
    sid    = "ReadWriteState"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      local.state_bucket_arn,
      "${local.state_bucket_arn}/*",
    ]
  }

  statement {
    sid    = "UseStateKmsKey"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]
    resources = [aws_kms_key.state.arn]
  }
}

resource "aws_iam_role_policy" "apply" {
  count = length(var.apply_role_trusted_principal_arns) > 0 ? 1 : 0

  name   = "state-read-write"
  role   = aws_iam_role.apply[0].id
  policy = data.aws_iam_policy_document.apply_role_permissions.json
}

# --- developer-readonly ---------------------------------------------------

data "aws_iam_policy_document" "developer_readonly_assume" {
  count = length(var.developer_readonly_trusted_principal_arns) > 0 ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = var.developer_readonly_trusted_principal_arns
    }
  }
}

resource "aws_iam_role" "developer_readonly" {
  count = length(var.developer_readonly_trusted_principal_arns) > 0 ? 1 : 0

  name               = "${var.account_name}-terraform-developer-readonly"
  assume_role_policy = data.aws_iam_policy_document.developer_readonly_assume[0].json
  tags               = var.tags
}

# Intentionally identical in scope to plan-role: read state, write only the
# lock file. A developer can run `terraform plan` locally to inspect drift;
# they can never run `terraform apply` with this role.
resource "aws_iam_role_policy" "developer_readonly" {
  count = length(var.developer_readonly_trusted_principal_arns) > 0 ? 1 : 0

  name   = "state-read-lockfile-write"
  role   = aws_iam_role.developer_readonly[0].id
  policy = data.aws_iam_policy_document.plan_role_permissions.json
}
