# Environment-level configuration for floci-local/us-east-1/dev.
#
# Mirrors live/nonprod/us-east-1/dev/env.hcl's structure exactly (ADR-002 —
# every environment reads the same shape of env.hcl). The only meaningful
# difference is account_name and the sandbox-only values below, which were
# already true for nonprod too — this environment is not "more local" than
# nonprod was designed to be, it just actually runs against Floci instead
# of a real (not-yet-existing) sandbox AWS account. See local/README.md.

locals {
  account_name = "floci-local"

  environment = "dev"
  aws_region  = "us-east-1"

  cost_center = "platform"
  team        = "platform"
  owner       = "jacksmartv"

  # --- account-foundation module inputs (Step 2) ---
  state_bucket_force_destroy  = true # local emulator only — never true in a real environment
  kms_deletion_window_in_days = 7    # AWS minimum; irrelevant to Floci's KMS emulation, kept for parity with nonprod

  kms_key_administrator_arns = []

  developer_readonly_trusted_principal_arns = []

  sso_instance_arn = null

  # --- github-oidc module inputs (Step 4) ---
  # Floci's EKS/STS/IAM emulation does not call out to the real GitHub
  # OIDC issuer — the aws_iam_openid_connect_provider resource and the
  # trust-policy shape are what's under test here, not a real GitHub
  # Actions run assuming this role. Kept as the real repo for parity
  # rather than a placeholder value.
  github_repository = "jacksmartv/aws-eks-v2"

  # --- network module inputs (Step 11) ---
  network_cidr_block = "10.0.0.0/16"
  network_azs        = ["us-east-1a", "us-east-1b", "us-east-1c"]

  network_public_subnets   = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
  network_private_subnets  = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
  network_database_subnets = ["10.0.20.0/24", "10.0.21.0/24", "10.0.22.0/24"]
  network_intra_subnets    = []

  network_nat_topology = "single"

  network_enable_s3_endpoint   = true
  network_enable_ecr_endpoints = true

  network_flow_logs_retention_days       = 14
  network_flow_logs_bucket_force_destroy = true
}
