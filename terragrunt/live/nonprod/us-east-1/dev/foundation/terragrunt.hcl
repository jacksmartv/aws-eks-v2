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

# github-oidc must apply before foundation — its plan/apply role ARNs feed
# directly into foundation's trust-principal inputs below. mock_outputs lets
# `terragrunt plan` on foundation work even before github-oidc has ever been
# applied (e.g. on a first `render`/`plan` dry run) — same dependency +
# mock_outputs pattern ADR-002 keeps from the original project's Terragrunt
# design.
dependency "github_oidc" {
  config_path = "../github-oidc"

  mock_outputs_allowed_terraform_commands = ["plan", "validate", "init"]
  mock_outputs = {
    plan_role_arn  = "arn:aws:iam::000000000000:role/mock-plan-role"
    apply_role_arn = "arn:aws:iam::000000000000:role/mock-apply-role"
  }
}

terraform {
  source = "../../../../../terraform/modules/account-foundation"
}

inputs = {
  account_name = local.account_vars.locals.account_name

  state_bucket_force_destroy  = local.env_vars.locals.state_bucket_force_destroy
  kms_deletion_window_in_days = local.env_vars.locals.kms_deletion_window_in_days
  kms_key_administrator_arns  = local.env_vars.locals.kms_key_administrator_arns

  plan_role_trusted_principal_arns          = [dependency.github_oidc.outputs.plan_role_arn]
  apply_role_trusted_principal_arns         = [dependency.github_oidc.outputs.apply_role_arn]
  developer_readonly_trusted_principal_arns = local.env_vars.locals.developer_readonly_trusted_principal_arns

  sso_instance_arn = local.env_vars.locals.sso_instance_arn

  tags = {
    Environment = local.env_vars.locals.environment
  }
}
