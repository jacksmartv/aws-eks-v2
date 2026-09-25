variable "github_repository" {
  description = "The GitHub repository allowed to assume roles created by this module, in \"org/repo\" format (e.g. \"jacksmartv/aws-eks-v2\"). Scopes every trust policy's `sub` condition — no other repository can assume these roles."
  type        = string
}

variable "create_oidc_provider" {
  description = "Whether to create the aws_iam_openid_connect_provider resource. Set to false if a GitHub Actions OIDC provider already exists in this AWS account (there can only be one per account per provider URL) and pass its ARN via existing_oidc_provider_arn instead."
  type        = bool
  default     = true
}

variable "existing_oidc_provider_arn" {
  description = "ARN of an existing GitHub Actions OIDC provider to use instead of creating a new one. Required when create_oidc_provider is false; ignored otherwise."
  type        = string
  default     = null
}

variable "plan_role_name" {
  description = "Name of the IAM role GitHub Actions assumes for plan-only CI runs (on every pull request)."
  type        = string
  default     = "github-actions-plan"
}

variable "apply_role_name" {
  description = "Name of the IAM role GitHub Actions assumes for the gated apply workflow."
  type        = string
  default     = "github-actions-apply"
}

variable "plan_role_ref_condition" {
  description = "The `token.actions.githubusercontent.com:sub` value(s) the plan role's trust policy accepts, as a StringLike condition. Default allows any ref in the named repository (pull requests included) — plan is read-only by design (see account-foundation's plan-role IAM policy), so a broad match here is deliberate, not a shortcut."
  type        = list(string)
  default     = null # computed from github_repository if not set — see locals
}

variable "apply_role_ref_condition" {
  description = "The `token.actions.githubusercontent.com:sub` value(s) the apply role's trust policy accepts, as a StringLike condition. Default restricts to the main branch only — apply must never be assumable from a pull request or an arbitrary branch. Override explicitly if a different branching model is used."
  type        = list(string)
  default     = null # computed from github_repository if not set — see locals
}

variable "tags" {
  description = "Tags applied to every resource this module creates, merged with default_tags set at the provider level."
  type        = map(string)
  default     = {}
}
