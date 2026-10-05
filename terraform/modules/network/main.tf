locals {
  enable_nat_gateway     = var.nat_topology != "none"
  single_nat_gateway     = var.nat_topology == "single"
  one_nat_gateway_per_az = var.nat_topology == "per_az"

  s3_endpoint = var.enable_s3_endpoint ? {
    s3 = {
      service      = "s3"
      service_type = "Gateway"
      route_table_ids = flatten([
        module.vpc.intra_route_table_ids,
        module.vpc.private_route_table_ids,
        module.vpc.public_route_table_ids,
      ])
    }
  } : {}

  ecr_endpoints = var.enable_ecr_endpoints ? {
    ecr_api = {
      service             = "ecr.api"
      service_type        = "Interface"
      subnet_ids          = module.vpc.private_subnets
      private_dns_enabled = true
    }
    ecr_dkr = {
      service             = "ecr.dkr"
      service_type        = "Interface"
      subnet_ids          = module.vpc.private_subnets
      private_dns_enabled = true
    }
  } : {}

  vpc_endpoints = merge(local.s3_endpoint, local.ecr_endpoints, var.additional_vpc_endpoints)

  # Any Interface endpoint in the merged map needs a security group — built
  # once here rather than per-endpoint, since every interface endpoint this
  # module creates (ECR API, ECR DKR) shares the same access pattern:
  # reachable from inside this VPC, nothing else.
  has_interface_endpoints = anytrue([
    for _, ep in local.vpc_endpoints : try(ep.service_type, "Interface") == "Interface"
  ])
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = var.name
  cidr = var.cidr_block
  azs  = var.azs

  public_subnets   = var.public_subnets
  private_subnets  = var.private_subnets
  database_subnets = var.database_subnets
  intra_subnets    = var.intra_subnets

  enable_nat_gateway     = local.enable_nat_gateway
  single_nat_gateway     = local.single_nat_gateway
  one_nat_gateway_per_az = local.one_nat_gateway_per_az

  enable_flow_log                   = true
  flow_log_destination_type         = "s3"
  flow_log_destination_arn          = aws_s3_bucket.flow_logs.arn
  flow_log_max_aggregation_interval = 600

  tags = var.tags
}

# VPC Flow Logs' S3 destination. The vpc module itself does not create this
# bucket — confirmed against its variables.tf (flow_log_destination_arn
# expects an ARN the caller already owns) — so this module owns it
# directly, keeping `network` self-contained rather than requiring a bucket
# to exist beforehand.
resource "aws_s3_bucket" "flow_logs" {
  bucket        = "${var.name}-vpc-flow-logs"
  force_destroy = var.flow_logs_bucket_force_destroy

  tags = merge(var.tags, {
    Name = "${var.name}-vpc-flow-logs"
  })
}

resource "aws_s3_bucket_public_access_block" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id

  rule {
    id     = "expire-flow-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.flow_logs_retention_days
    }
  }
}

# Required for VPC Flow Logs to deliver to this bucket — the exact
# principal, actions, and conditions AWS's own VPC Flow Logs documentation
# specifies for S3 delivery (not CloudTrail's or another log-delivery
# service's policy shape, which differ). The aws:SourceArn condition is
# intentionally scoped to CloudWatch Logs ARNs (arn:aws:logs:<region>:
# <account>:*), per AWS's own documented policy — not this VPC's or this
# bucket's ARN — because the log delivery service's confused-deputy
# protection is keyed off the log-delivery-service ARN space, not the
# destination.
data "aws_iam_policy_document" "flow_logs_bucket_policy" {
  statement {
    sid    = "AWSLogDeliveryWrite"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.flow_logs.arn}/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:*"]
    }
  }

  statement {
    sid    = "AWSLogDeliveryAclCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.flow_logs.arn]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:*"]
    }
  }
}

resource "aws_s3_bucket_policy" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs_bucket_policy.json
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Interface endpoints (ECR API, ECR DKR, and anything added via
# additional_vpc_endpoints that doesn't bring its own security_group_ids)
# need a security group. Built once, shared by every Interface endpoint in
# the merged map, scoped to HTTPS from inside this VPC only.
resource "aws_security_group" "vpc_endpoints" {
  count = local.has_interface_endpoints ? 1 : 0

  name        = "${var.name}-vpc-endpoints"
  description = "Allows HTTPS from inside this VPC to interface VPC endpoints (ECR, etc.)"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTPS from within the VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.cidr_block]
  }

  tags = merge(var.tags, {
    Name = "${var.name}-vpc-endpoints"
  })
}

module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 6.0"

  count = length(local.vpc_endpoints) > 0 ? 1 : 0

  vpc_id = module.vpc.vpc_id

  security_group_ids = local.has_interface_endpoints ? [aws_security_group.vpc_endpoints[0].id] : []

  endpoints = local.vpc_endpoints

  tags = var.tags
}
