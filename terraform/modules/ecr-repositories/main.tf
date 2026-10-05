locals {
  # terraform-aws-modules/ecr/aws has no native multi-repository mechanism
  # (confirmed against its real variables.tf: a singular repository_name,
  # resource count capped at 1) — this for_each, one module instance per
  # repo name, is this module's own doing, not something the upstream
  # module provides.
  #
  # Keys are full repository name strings ("dev/ts-admin-tickets"), never
  # list indices — for_each over a set of stable strings means adding or
  # removing one namespace/repo only creates/destroys that one entry,
  # never recreates the others (verified directly: adding a namespace to
  # an already-applied set of repos produced a plan with 0 changes to the
  # existing entries, only new adds).
  repositories = toset(
    length(var.ecr_namespaces) == 0
    ? var.repository_names
    : [
      for pair in setproduct(var.ecr_namespaces, var.repository_names) : "${pair[0]}/${pair[1]}"
    ]
  )

  # ECR's own lifecycle policy schema (AWS ECR User Guide, "Lifecycle
  # policy parameters"): countNumber must be a JSON number, not a string —
  # jsonencode() renders it correctly as long as the Terraform value is
  # typed `number`, which lifecycle_policy_keep_last_n already is.
  lifecycle_policy_json = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.lifecycle_policy_keep_last_n} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.lifecycle_policy_keep_last_n
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

module "ecr" {
  source  = "terraform-aws-modules/ecr/aws"
  version = "~> 3.2"

  for_each = local.repositories

  repository_name = each.value

  repository_image_tag_mutability = var.image_tag_mutability
  repository_image_scan_on_push   = var.scan_on_push

  create_lifecycle_policy     = true
  repository_lifecycle_policy = local.lifecycle_policy_json

  repository_force_delete = var.repository_force_delete

  tags = var.tags
}
