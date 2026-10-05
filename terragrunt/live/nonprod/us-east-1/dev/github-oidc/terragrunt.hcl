include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

# github-oidc is the one unit in this account with a bootstrap-ordering
# problem: it must be applied BEFORE account-foundation (account-foundation
# needs its plan/apply role ARNs), but account-foundation is what creates
# the shared S3 state bucket (`<account_name>-terraform-state`) that
# root.hcl's remote_state block points every other unit's backend at. A
# bucket that doesn't exist yet can't hold this unit's own state — a real
# circular bootstrap dependency, not specific to this project's design.
#
# The resolution, confirmed against the standard pattern used by
# HashiCorp's own docs and real Terragrunt reference architectures (e.g.
# bezilla/terragrunt-reference-architecture's ADR on this exact problem):
# the unit that must exist before the shared backend exists keeps LOCAL
# state PERMANENTLY, deliberately, instead of ever joining the shared S3
# backend. This remote_state block overrides (not merges with) the S3
# block root.hcl's "root" include would otherwise generate.
#
# Consequences, by design:
# - This unit is applied by hand, only, by a human with real SSO
#   credentials — never by CI (see .github/workflows/terraform-apply.yml,
#   which is itself manual-only for now) and never via `terragrunt run-all`
#   (its state lives on disk, not in any shared bucket `run-all` could
#   discover).
# - Its `.tfstate` is NOT gitignored like every other unit's — see the
#   repo root .gitignore's `*.tfstate` exclusion and its explicit carve-out
#   comment for this file. It's small (one OIDC provider + two IAM roles)
#   and contains nothing secret, the same reasoning
#   trussworks/terraform-aws-bootstrap documents for its own
#   permanently-local bootstrap state.
# - It is excluded from terragrunt/root.hcl's remote_state generation
#   entirely, not just pointed at a different bucket — there is no bucket
#   to point at before account-foundation exists.
#
# config.path is anchored with get_terragrunt_dir() deliberately, not a
# bare relative "terraform.tfstate" — Terragrunt v1.x always runs Terraform
# from inside .terragrunt-cache/<random-hash>/<random-hash>/ (confirmed:
# there is no way to opt out of this in v1.1.6, unlike the pre-v1 behavior
# where omitting `source` ran Terraform in place; see
# https://github.com/gruntwork-io/terragrunt/issues/6199). A relative path
# would resolve inside that ephemeral, randomly-named cache directory,
# which is deleted and recreated on every `init` — making "permanent local
# state" silently false despite the comment above. get_terragrunt_dir()
# returns this file's own real directory, so the state file always lands
# in the same stable, version-controlled location regardless of which
# cache directory Terraform actually executes in.
remote_state {
  backend = "local"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    path = "${get_terragrunt_dir()}/terraform.tfstate"
  }
}

terraform {
  source = "../../../../../../terraform/modules/github-oidc"
}

inputs = {
  github_repository = local.env_vars.locals.github_repository
}
