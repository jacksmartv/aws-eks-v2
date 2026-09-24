# Root Terragrunt configuration.
#
# Every unit in terragrunt/live/**/*.hcl includes this file. It generates
# two things for all of them: the S3 backend block (native locking, no
# DynamoDB — see MASTERPLAN.md/ASSESSMENT.md for the state-locking decision)
# and the AWS provider block, including the mandatory default_tags this
# project requires on every resource (see MASTERPLAN.md §6, Cost
# Architecture — added after auditing a real production fork that ran for
# years without any cost-attribution tagging beyond Name/Environment).
#
# This file holds generation logic only — no account- or environment-
# specific data. That lives in _accounts/<account>/account.hcl and
# live/<account>/<region>/<env>/env.hcl, per ADR-002.

locals {
  # env.hcl lives in a real parent folder of every unit (live/<account>/
  # <region>/<env>/), so find_in_parent_folders() finds it by walking up.
  # _accounts/<account>/account.hcl does NOT — it's a sibling branch of the
  # tree, not an ancestor of any unit — so its path is built explicitly
  # from this root file's own location plus the account name env.hcl
  # declares. This keeps account.hcl itself as pure data (ADR-002): no unit
  # hardcodes an account path, they all derive it from env.hcl's
  # account_name the same way.
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  # env.hcl's own directory is live/<account>/<region>/<env>/ — four levels
  # up from there is the terragrunt/ root, where _accounts/ lives.
  account_vars = read_terragrunt_config(
    "${dirname(find_in_parent_folders("env.hcl"))}/../../../../_accounts/${local.env_vars.locals.account_name}/account.hcl"
  )

  account_name = local.account_vars.locals.account_name
  account_id   = local.account_vars.locals.account_id
  aws_region   = local.env_vars.locals.aws_region

  # NEVER emit allowed_account_ids = [""] — an empty-string entry is not
  # "no restriction," it's a hard block: the AWS provider compares it
  # against the real account ID with a simple equality check, so an empty
  # string never matches anything and every plan/apply/destroy fails before
  # touching any resource. Only emit the argument once account_id is
  # actually populated (see _accounts/<account>/account.hcl, left blank
  # deliberately until a real sandbox account exists).
  allowed_account_ids_block = local.account_id != "" ? "allowed_account_ids = [\"${local.account_id}\"]" : ""
}

remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket = "${local.account_name}-terraform-state"
    key    = "${path_relative_to_include()}/terraform.tfstate"
    region = local.aws_region

    encrypt      = true
    use_lockfile = true # S3 native locking (Terraform >= 1.11) — no DynamoDB table anywhere in this project
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws" {
      region = "${local.aws_region}"
      ${local.allowed_account_ids_block}

      default_tags {
        tags = {
          ManagedBy   = "terraform"
          Project     = "aws-eks-base-v2"
          Environment = "${local.env_vars.locals.environment}"
          CostCenter  = "${local.env_vars.locals.cost_center}"
          Team        = "${local.env_vars.locals.team}"
          Owner       = "${local.env_vars.locals.owner}"
        }
      }
    }
  EOF
}
