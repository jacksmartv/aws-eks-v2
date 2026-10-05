variable "repository_names" {
  description = "Real app-repo names to create an ECR repository for — e.g. [\"ts-admin-tickets\", \"front/ts-admin-seated-ticketing\"]. Use the app's actual name, not a generic placeholder (see README). This is the only place that decides which apps have an ECR repository in this account/region/environment."
  type        = list(string)

  validation {
    condition     = length(var.repository_names) == length(distinct(var.repository_names))
    error_message = "repository_names must not contain duplicates."
  }
}

variable "ecr_namespaces" {
  description = <<-EOT
    Environment namespaces to prefix every repository_names entry with, replicating TicketSocket v1's real pattern (one AWS account for every environment, environment encoded as a path prefix: "$${namespace}$${repo_name}" — e.g. "dev/ts-admin-tickets").

    Empty (default): this project's own default model — one account per environment (ADR-002) — so no namespace prefix is needed; repository_names are created exactly as given.
    Non-empty: creates the full cartesian product of ecr_namespaces × repository_names — one repository per (namespace, repo) pair, e.g. ["dev", "staging"] × ["ts-admin-tickets"] creates "dev/ts-admin-tickets" and "staging/ts-admin-tickets" both in this one account.

    Only set this if this account is shared across multiple environments — not the default/recommended model, but a real pattern this project doesn't force a migration away from. See README.
  EOT
  type        = list(string)
  default     = []
}

variable "image_tag_mutability" {
  description = "MUTABLE or IMMUTABLE. Applies to every repository this module creates."
  type        = string
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be \"MUTABLE\" or \"IMMUTABLE\"."
  }
}

variable "scan_on_push" {
  description = "Whether ECR scans images for vulnerabilities on push. Applies to every repository this module creates."
  type        = bool
  default     = true
}

variable "lifecycle_policy_keep_last_n" {
  description = "How many most-recent images to keep per repository before ECR expires older ones — TicketSocket v1's existing pattern (\"keep last N images\", tagStatus \"any\"), kept as this project's reference default. N=10, matching v1's own default."
  type        = number
  default     = 10

  validation {
    condition     = var.lifecycle_policy_keep_last_n > 0
    error_message = "lifecycle_policy_keep_last_n must be a positive integer (ECR's own lifecycle policy schema rejects 0 or negative)."
  }
}

variable "repository_force_delete" {
  description = "Whether `terraform destroy` can remove a repository even if it still contains images. Sandbox/testing only — never true in a real environment, same reasoning as account-foundation's state_bucket_force_destroy."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to every repository this module creates, merged with the AWS provider's own default_tags (see terragrunt/root.hcl)."
  type        = map(string)
  default     = {}
}
