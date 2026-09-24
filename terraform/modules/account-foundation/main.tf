locals {
  state_bucket_name = coalesce(var.state_bucket_name, "${var.account_name}-terraform-state")
}

# ---------------------------------------------------------------------------
# Terraform state backend
#
# One bucket per account, not per environment — environment isolation is via
# key prefix (<region>/<env>/<unit>/terraform.tfstate), not separate buckets.
# See MASTERPLAN.md §1.1 for the full reasoning.
#
# Locking is S3 native locking (Terraform >= 1.11, use_lockfile = true, set
# at the backend-config level by whatever consumes this module's outputs) —
# no DynamoDB table.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "state" {
  bucket        = local.state_bucket_name
  force_destroy = var.state_bucket_force_destroy

  tags = merge(var.tags, {
    Name    = local.state_bucket_name
    Purpose = "terraform-state"
  })
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# KMS customer-managed keys
# ---------------------------------------------------------------------------

resource "aws_kms_key" "state" {
  description             = "Encrypts the Terraform state bucket for account: ${var.account_name}"
  deletion_window_in_days = var.kms_deletion_window_in_days
  enable_key_rotation     = true

  policy = data.aws_iam_policy_document.state_kms_key_policy.json

  tags = merge(var.tags, {
    Name    = "${var.account_name}-state-key"
    Purpose = "terraform-state-encryption"
  })
}

resource "aws_kms_alias" "state" {
  name          = "alias/${var.account_name}-terraform-state"
  target_key_id = aws_kms_key.state.key_id
}

resource "aws_kms_key" "ebs" {
  description             = "Default EBS volume encryption key for account: ${var.account_name}"
  deletion_window_in_days = var.kms_deletion_window_in_days
  enable_key_rotation     = true

  policy = data.aws_iam_policy_document.ebs_kms_key_policy.json

  tags = merge(var.tags, {
    Name    = "${var.account_name}-ebs-key"
    Purpose = "ebs-default-encryption"
  })
}

resource "aws_kms_alias" "ebs" {
  name          = "alias/${var.account_name}-ebs-default"
  target_key_id = aws_kms_key.ebs.key_id
}

resource "aws_ebs_encryption_by_default" "this" {
  enabled = true
}

resource "aws_ebs_default_kms_key" "this" {
  key_arn = aws_kms_key.ebs.arn
}

data "aws_caller_identity" "current" {}

# Shared base: root account access + optional key administrators. Reused by
# both key policies below via source_policy_documents, each of which adds
# its own service-principal statement on top.
data "aws_iam_policy_document" "kms_key_administrators_base" {
  # Root account always retains full access — required so the key is never
  # locked out from its own account if the administrator ARN list is wrong.
  statement {
    sid    = "EnableRootAccountFullAccess"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = length(var.kms_key_administrator_arns) > 0 ? [1] : []
    content {
      sid    = "AllowKeyAdministration"
      effect = "Allow"
      principals {
        type        = "AWS"
        identifiers = var.kms_key_administrator_arns
      }
      actions = [
        "kms:Create*", "kms:Describe*", "kms:Enable*", "kms:List*",
        "kms:Put*", "kms:Update*", "kms:Revoke*", "kms:Disable*",
        "kms:Get*", "kms:Delete*", "kms:TagResource", "kms:UntagResource",
        "kms:ScheduleKeyDeletion", "kms:CancelKeyDeletion",
        "kms:RotateKeyOnDemand",
      ]
      resources = ["*"]
    }
  }
}

# Explicit grant for the S3 service to use this key for SSE-KMS on the state
# bucket. Without this, encryption currently still works only because the
# root-account statement above implicitly covers it — that's an implicit
# dependency, not a guaranteed one if this policy is ever tightened. Scoped
# via kms:ViaService + a source-account condition so only S3 requests
# originating from this account can use the key.
data "aws_iam_policy_document" "state_kms_key_policy" {
  source_policy_documents = [data.aws_iam_policy_document.kms_key_administrators_base.json]

  statement {
    sid    = "AllowS3ServiceToUseKeyForStateBucketEncryption"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${data.aws_region.current.name}.amazonaws.com"]
    }
  }
}

# Same pattern for the EBS service, needed for account-level default EBS
# encryption (aws_ebs_default_kms_key) to actually work against this key.
data "aws_iam_policy_document" "ebs_kms_key_policy" {
  source_policy_documents = [data.aws_iam_policy_document.kms_key_administrators_base.json]

  statement {
    sid    = "AllowEbsServiceToUseKeyForDefaultEncryption"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey*",
      "kms:CreateGrant",
      "kms:DescribeKey",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ec2.${data.aws_region.current.name}.amazonaws.com"]
    }
  }
}

data "aws_region" "current" {}
