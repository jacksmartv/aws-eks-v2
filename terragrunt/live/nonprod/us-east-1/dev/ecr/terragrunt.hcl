include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

# No dependency block — ecr doesn't read any output from foundation or
# network, same reasoning as network's own terragrunt.hcl.
terraform {
  source = "../../../../../../terraform/modules/ecr-repositories"
}

inputs = {
  repository_names = local.env_vars.locals.ecr_repository_names
  ecr_namespaces   = local.env_vars.locals.ecr_namespaces

  image_tag_mutability = local.env_vars.locals.ecr_image_tag_mutability
  scan_on_push         = local.env_vars.locals.ecr_scan_on_push

  lifecycle_policy_keep_last_n = local.env_vars.locals.ecr_lifecycle_policy_keep_last_n

  repository_force_delete = local.env_vars.locals.ecr_repository_force_delete

  tags = {
    Environment = local.env_vars.locals.environment
  }
}
