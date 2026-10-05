include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

# No dependency block — network doesn't read any output from foundation.
# The real ordering (foundation applies first, same account-level
# bootstrap every unit beyond foundation/github-oidc assumes) is
# documented, not enforced via a Terragrunt dependency, since no data
# actually flows between the two units.
terraform {
  source = "../../../../../../terraform/modules/network"
}

inputs = {
  name       = "${local.env_vars.locals.account_name}-${local.env_vars.locals.environment}"
  cidr_block = local.env_vars.locals.network_cidr_block
  azs        = local.env_vars.locals.network_azs

  public_subnets   = local.env_vars.locals.network_public_subnets
  private_subnets  = local.env_vars.locals.network_private_subnets
  database_subnets = local.env_vars.locals.network_database_subnets
  intra_subnets    = local.env_vars.locals.network_intra_subnets

  nat_topology = local.env_vars.locals.network_nat_topology

  enable_s3_endpoint   = local.env_vars.locals.network_enable_s3_endpoint
  enable_ecr_endpoints = local.env_vars.locals.network_enable_ecr_endpoints

  flow_logs_retention_days       = local.env_vars.locals.network_flow_logs_retention_days
  flow_logs_bucket_force_destroy = local.env_vars.locals.network_flow_logs_bucket_force_destroy

  tags = {
    Environment = local.env_vars.locals.environment
  }
}
