# Account-level configuration for "floci-local" — not a real AWS account.
#
# This account exists only to exercise this project's Terragrunt/Terraform
# units against Floci (https://github.com/floci-io/floci), a free local
# AWS emulator, running via local/docker-compose.yml. It follows the exact
# same account -> region -> environment -> unit hierarchy (ADR-002) as any
# real account — nothing in root.hcl, any unit's terragrunt.hcl, or any
# terraform/modules/* module is aware this is a local emulator rather than
# real AWS. See local/README.md for how the two connect.
#
# account_id is a synthetic 12-digit value, deliberately distinct from
# this project's one real AWS account (184086410155), so the two can
# never be confused in a shell history, a pasted ARN, or a screenshot.
# Floci's multi-account isolation uses a 12-digit access key ID directly
# as the account ID (see local/.env.example) — this value must match that
# access key ID exactly, or resources land in Floci's default account
# namespace instead of this one.

locals {
  account_name = "floci-local"

  account_id = "111111111111"

  # Local investigation only — never the payer/management account of
  # anything real. See MASTERPLAN.md §6 for what this flag controls on a
  # real account.
  is_payer_account = false
}
