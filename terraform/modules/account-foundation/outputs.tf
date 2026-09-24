output "state_bucket_name" {
  description = "Name of the S3 bucket used as the Terraform state backend for this account. Pass this into each unit's backend configuration."
  value       = aws_s3_bucket.state.id
}

output "state_bucket_arn" {
  description = "ARN of the Terraform state bucket."
  value       = aws_s3_bucket.state.arn
}

output "state_kms_key_arn" {
  description = "ARN of the KMS key encrypting the state bucket."
  value       = aws_kms_key.state.arn
}

output "ebs_kms_key_arn" {
  description = "ARN of the KMS key used as the account's default EBS encryption key. Reused by the EKS cluster module for node volume encryption."
  value       = aws_kms_key.ebs.arn
}

output "plan_role_arn" {
  description = "ARN of the plan-role, or null if plan_role_trusted_principal_arns was empty. Used by the CI plan workflow."
  value       = try(aws_iam_role.plan[0].arn, null)
}

output "apply_role_arn" {
  description = "ARN of the apply-role, or null if apply_role_trusted_principal_arns was empty. Used by the CI apply workflow — must stay gated behind GitHub Environments."
  value       = try(aws_iam_role.apply[0].arn, null)
}

output "developer_readonly_role_arn" {
  description = "ARN of the developer-readonly role, or null if developer_readonly_trusted_principal_arns was empty."
  value       = try(aws_iam_role.developer_readonly[0].arn, null)
}
