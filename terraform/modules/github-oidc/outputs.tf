output "oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider used (newly created, or the existing one passed in via existing_oidc_provider_arn)."
  value       = local.oidc_provider_arn
}

output "plan_role_arn" {
  description = "ARN of the plan role. Pass this into account-foundation's plan_role_trusted_principal_arns."
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "ARN of the apply role. Pass this into account-foundation's apply_role_trusted_principal_arns."
  value       = aws_iam_role.apply.arn
}
