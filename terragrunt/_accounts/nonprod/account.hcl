# Account-level configuration for the "nonprod" AWS account.
#
# Data only — no provider logic, no resource-shaping conditionals. See
# ADR-002: environment-specific behavior flows into a module as a variable
# value, never as an `if` inside an .hcl include.
#
# account_id is intentionally left as a placeholder until a real sandbox
# account exists. While it's empty, root.hcl deliberately
# omits the AWS provider's allowed_account_ids guard entirely (an empty
# string there would hard-block every plan/apply against ANY account, not
# just this one — see terragrunt/root.hcl for why). That means an
# empty account_id gives NO account-mismatch protection at all: whatever
# AWS credentials happen to be active is exactly the account this would
# apply against. Fill in the real account ID as the first step of using
# this account for anything beyond a `terragrunt render` dry run.

locals {
  account_name = "nonprod"

  # Replace with the real AWS account ID before running any `terragrunt
  # apply` against this account. Left blank deliberately — there is no safe
  # default for an AWS account ID.
  account_id = ""

  # Whether this is the AWS Organizations payer/management account. Only
  # one account in the whole hierarchy should ever set this true (see
  # MASTERPLAN.md §6 — cost-allocation-tag activation is scoped to the
  # payer account only, mirroring a real pattern confirmed by auditing a
  # production fork of this project).
  is_payer_account = false
}
