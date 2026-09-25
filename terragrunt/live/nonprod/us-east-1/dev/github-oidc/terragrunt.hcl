include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

terraform {
  source = "../../../../../terraform/modules/github-oidc"
}

inputs = {
  github_repository = local.env_vars.locals.github_repository
}
