include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  # See terragrunt/root.hcl for why account.hcl can't be found via
  # find_in_parent_folders() — it's a sibling branch of the tree (_accounts/),
  # not an ancestor of this unit.
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  # env.hcl's directory is live/<account>/<region>/<env>/ — four levels up
  # from there is the terragrunt/ root, where _accounts/ lives.
  account_vars = read_terragrunt_config(
    "${dirname(find_in_parent_folders("env.hcl"))}/../../../../_accounts/${local.env_vars.locals.account_name}/account.hcl"
  )
}

terraform {
  source = "../../../../../terraform/modules/account-foundation"
}

inputs = {
  account_name = local.account_vars.locals.account_name

  state_bucket_force_destroy  = local.env_vars.locals.state_bucket_force_destroy
  kms_deletion_window_in_days = local.env_vars.locals.kms_deletion_window_in_days
  kms_key_administrator_arns  = local.env_vars.locals.kms_key_administrator_arns

  plan_role_trusted_principal_arns          = local.env_vars.locals.plan_role_trusted_principal_arns
  apply_role_trusted_principal_arns         = local.env_vars.locals.apply_role_trusted_principal_arns
  developer_readonly_trusted_principal_arns = local.env_vars.locals.developer_readonly_trusted_principal_arns

  sso_instance_arn = local.env_vars.locals.sso_instance_arn

  tags = {
    Environment = local.env_vars.locals.environment
  }
}
