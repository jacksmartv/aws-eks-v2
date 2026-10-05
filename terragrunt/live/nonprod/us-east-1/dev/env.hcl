# Environment-level configuration for nonprod/us-east-1/dev.
#
# This is the single file every unit in this environment reads (foundation,
# network, ecr, eks-cluster, gitops-bootstrap — see MASTERPLAN.md §3). Data
# only, per ADR-002 — no provider logic, no conditionals shaping resources.
# Change a value here once; every unit in this environment picks it up via
# `include`/`read_terragrunt_config`, without duplicating it per-unit.

locals {
  # Which _accounts/<account_name>/account.hcl this environment belongs to.
  # root.hcl resolves account.hcl's path from this value — see
  # terragrunt/root.hcl for why (account.hcl is a sibling branch of the
  # tree, not an ancestor of any unit, so find_in_parent_folders() can't
  # locate it on its own).
  account_name = "nonprod"

  environment = "dev"
  aws_region  = "us-east-1"

  # Cost-allocation tags, applied to every resource in this environment via
  # root.hcl's provider default_tags block. See MASTERPLAN.md
  # §6 — added specifically because auditing a real production fork of this
  # project found years of resources tagged with nothing beyond
  # Name/Environment, making after-the-fact cost attribution impossible.
  cost_center = "platform"
  team        = "platform"
  owner       = "jacksmartv"

  # --- account-foundation module inputs (Step 2) ---
  state_bucket_force_destroy  = true # sandbox only — never true in a real environment
  kms_deletion_window_in_days = 7    # AWS minimum; sandbox only — use 30 in real environments

  kms_key_administrator_arns = []

  # plan_role_trusted_principal_arns / apply_role_trusted_principal_arns are
  # NOT set here — foundation/terragrunt.hcl gets them from the github-oidc
  # unit's outputs via a Terragrunt `dependency` block (Step 4), not from
  # this file. Those two roles don't exist as static data; they're created
  # by Terraform, so their ARNs have to come from that unit's real output,
  # not be guessed/hardcoded in env.hcl.
  developer_readonly_trusted_principal_arns = []

  sso_instance_arn = null

  # --- github-oidc module inputs (Step 4) ---
  # "org/repo" the OIDC trust policies are scoped to — no other GitHub
  # repository can assume the plan/apply roles this unit creates.
  github_repository = "jacksmartv/aws-eks-v2"

  # --- network module inputs (Step 11) ---
  network_cidr_block = "10.0.0.0/16"
  network_azs        = ["us-east-1a", "us-east-1b", "us-east-1c"]

  network_public_subnets   = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
  network_private_subnets  = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
  network_database_subnets = ["10.0.20.0/24", "10.0.21.0/24", "10.0.22.0/24"]
  network_intra_subnets    = []

  network_nat_topology = "single" # sandbox only — use "per_az" in a real environment

  network_enable_s3_endpoint   = true
  network_enable_ecr_endpoints = true

  network_flow_logs_retention_days       = 14
  network_flow_logs_bucket_force_destroy = true # sandbox only — never true in a real environment

  # --- ecr-repositories module inputs (Step 12) ---
  # The only place that decides which apps have an ECR repository in this
  # account/region/environment — adding an app is a line here, not a
  # module edit. Real TicketSocket app names, not placeholders.
  ecr_repository_names = [
    "ts-admin-tickets",
    "front/ts-admin-seated-ticketing",
  ]

  # Empty = this project's default model (one account per environment,
  # ADR-002) — no namespace prefix needed. Populate only if this account
  # is shared across multiple environments, TicketSocket v1's real model.
  ecr_namespaces = []

  ecr_image_tag_mutability = "IMMUTABLE"
  ecr_scan_on_push         = true

  ecr_lifecycle_policy_keep_last_n = 10 # TicketSocket v1's own default

  ecr_repository_force_delete = true # sandbox only — never true in a real environment
}
