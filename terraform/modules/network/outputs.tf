output "vpc_id" {
  description = "ID of the VPC. Needed by eks-cluster and any other unit that attaches resources to this network."
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC."
  value       = module.vpc.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets, one per AZ in var.azs."
  value       = module.vpc.public_subnets
}

output "private_subnet_ids" {
  description = "IDs of the private subnets. Where EKS nodes and most workloads live — see eks-cluster's own README once that module exists for the exact inputs it expects from this module."
  value       = module.vpc.private_subnets
}

output "database_subnet_ids" {
  description = "IDs of the database subnets. Empty list if var.database_subnets was empty."
  value       = module.vpc.database_subnets
}

output "intra_subnet_ids" {
  description = "IDs of the intra subnets (fully isolated, no NAT/IGW route). Empty list if var.intra_subnets was empty."
  value       = module.vpc.intra_subnets
}

output "nat_gateway_ids" {
  description = "IDs of the NAT gateways created, if any (empty list when nat_topology = \"none\")."
  value       = module.vpc.natgw_ids
}

output "flow_logs_bucket_name" {
  description = "Name of the S3 bucket VPC Flow Logs are delivered to."
  value       = aws_s3_bucket.flow_logs.id
}

output "flow_logs_bucket_arn" {
  description = "ARN of the Flow Logs S3 bucket."
  value       = aws_s3_bucket.flow_logs.arn
}

output "vpc_endpoints_security_group_id" {
  description = "ID of the security group attached to interface VPC endpoints (ECR, etc.), or null if no interface endpoint was created."
  value       = length(aws_security_group.vpc_endpoints) > 0 ? aws_security_group.vpc_endpoints[0].id : null
}
