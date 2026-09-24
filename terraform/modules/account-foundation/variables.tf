variable "account_name" {
  description = "Short, human-readable name for the AWS account this module runs in (e.g. \"nonprod\", \"prod\", \"shared-services\"). Used as a prefix for all resource names."
  type        = string
}

variable "state_bucket_name" {
  description = "Name of the S3 bucket used as the Terraform state backend for this account. Must be globally unique. If null, a name is derived from account_name."
  type        = string
  default     = null
}

variable "state_bucket_force_destroy" {
  description = "Whether the state bucket can be destroyed even if it contains objects. Must stay false outside of throwaway sandbox accounts — this bucket holds the state for every environment in the account."
  type        = bool
  default     = false
}

variable "kms_deletion_window_in_days" {
  description = "Waiting period, in days, before a KMS key scheduled for deletion is actually deleted. AWS allows 7-30."
  type        = number
  default     = 30
}

variable "kms_key_administrator_arns" {
  description = "IAM principal ARNs (roles or users) granted administrative access to the account's KMS keys (rotate, disable, schedule deletion). Should be a small, deliberate list — not a broad admin role."
  type        = list(string)
  default     = []
}

# --- State access roles (see MASTERPLAN.md §1.1 for the full reasoning) ---

variable "plan_role_trusted_principal_arns" {
  description = "IAM principal ARNs allowed to assume the plan-role via sts:AssumeRole (typically a GitHub Actions OIDC provider's role, scoped to this repository). Read-only on state; write access is limited to the S3 native lock file."
  type        = list(string)
  default     = []
}

variable "apply_role_trusted_principal_arns" {
  description = "IAM principal ARNs allowed to assume the apply-role. Should be scoped as narrowly as possible — typically only the GitHub Actions OIDC role used by the gated terraform-apply.yml workflow, never a human or a local-dev role."
  type        = list(string)
  default     = []
}

variable "developer_readonly_trusted_principal_arns" {
  description = "IAM principal ARNs (typically human SSO permission sets) allowed to assume the developer-readonly role for local debugging. Same permission scope as plan-role — read-only, lock-file write only. Never grant apply-role-equivalent access here."
  type        = list(string)
  default     = []
}

variable "sso_instance_arn" {
  description = "ARN of the AWS IAM Identity Center (SSO) instance for this account, if one is managed via Terraform here. Left null until a real sandbox/production SSO instance exists — the module works without it; this variable is a placeholder for that wiring, not a hard requirement."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to every resource this module creates, merged with default_tags set at the provider level (CostCenter/Team/Owner — see MASTERPLAN.md §6). This variable is for module-specific tags only; do not duplicate provider-level default_tags here."
  type        = map(string)
  default     = {}
}
