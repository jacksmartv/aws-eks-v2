include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

# Same bootstrap-ordering exception as live/nonprod/us-east-1/dev/github-oidc
# — see that file's comment for the full explanation. github-oidc must
# apply before foundation, but foundation is what creates the shared S3
# state bucket every other unit's backend points at, so this unit keeps
# local state permanently rather than joining that backend.
remote_state {
  backend = "local"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    # get_terragrunt_dir() anchors this to this file's own real directory
    # — see live/nonprod/.../github-oidc/terragrunt.hcl's comment for why
    # a bare relative path breaks (it would resolve inside the ephemeral,
    # randomly-named .terragrunt-cache directory Terraform actually runs
    # in, which Terragrunt v1.x deletes/recreates on every `init`).
    path = "${get_terragrunt_dir()}/terraform.tfstate"
  }
}

terraform {
  source = "../../../../../../terraform/modules/github-oidc"
}

inputs = {
  github_repository = local.env_vars.locals.github_repository
}
