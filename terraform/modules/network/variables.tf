variable "name" {
  description = "Name for the VPC and its resources (e.g. \"nonprod-dev\"). Used as a tag/name prefix, not an AWS-enforced identifier."
  type        = string
}

variable "cidr_block" {
  description = "CIDR block for the VPC."
  type        = string
}

variable "azs" {
  description = "Availability zones to spread subnets across. Determines how many subnets of each enabled tier get created — one per AZ."
  type        = list(string)
}

variable "public_subnets" {
  description = "CIDR blocks for public subnets, one per entry. Length must match var.azs if non-empty."
  type        = list(string)
  default     = []
}

variable "private_subnets" {
  description = "CIDR blocks for private subnets (outbound via NAT, no direct inbound from the internet)."
  type        = list(string)
  default     = []
}

variable "database_subnets" {
  description = "CIDR blocks for database subnets (no route to the internet at all, not even via NAT). A DB subnet group is created automatically when this is non-empty."
  type        = list(string)
  default     = []
}

variable "intra_subnets" {
  description = "CIDR blocks for intra subnets — fully isolated, no NAT/IGW route of any kind. For resources that must never reach the internet, inbound or outbound."
  type        = list(string)
  default     = []
}

variable "nat_topology" {
  description = <<-EOT
    How NAT gateways are provisioned for private-subnet outbound traffic:
      "none"    - no NAT gateway at all (private subnets have no internet egress)
      "single"  - one NAT gateway for the whole VPC (cheapest, single point of failure)
      "per_az"  - one NAT gateway per availability zone (higher cost, no cross-AZ data transfer for NAT traffic, no single point of failure)
    No default — every environment sets this explicitly, same reasoning as this project's compute_mode variable (ADR-003): a silent default here would hide a real cost/resilience tradeoff.
  EOT
  type        = string

  validation {
    condition     = contains(["none", "single", "per_az"], var.nat_topology)
    error_message = "nat_topology must be one of: \"none\", \"single\", \"per_az\"."
  }
}

variable "enable_s3_endpoint" {
  description = "Create an S3 gateway VPC endpoint (no hourly cost, routes S3 traffic off the NAT gateway/internet path entirely)."
  type        = bool
  default     = true
}

variable "enable_ecr_endpoints" {
  description = "Create ECR API + ECR DKR interface VPC endpoints, so nodes/tasks in private subnets can pull images without a NAT gateway on the path."
  type        = bool
  default     = true
}

variable "additional_vpc_endpoints" {
  description = <<-EOT
    Extra VPC endpoints beyond the S3/ECR pair this module already knows how to build — e.g. DynamoDB, SSM, STS. Same map shape terraform-aws-modules/vpc/aws's vpc-endpoints submodule itself expects (one entry per endpoint; each entry's own keys — service, service_type, subnet_ids, route_table_ids, private_dns_enabled — follow that submodule's interface directly, since this project doesn't have an opinion about every possible endpoint the way it does about S3/ECR).
    Empty by default. This is an escape hatch for endpoints this module hasn't been taught about yet, not the primary way to configure S3/ECR — use enable_s3_endpoint/enable_ecr_endpoints for those.
  EOT
  type        = any
  default     = {}
}

variable "flow_logs_retention_days" {
  description = "How many days to retain VPC Flow Logs in the S3 destination bucket before an S3 lifecycle rule expires them. Short by design (ASSESSMENT.md/MASTERPLAN.md §2: basic connectivity-debugging visibility, not a long-term audit trail)."
  type        = number
  default     = 14

  validation {
    condition     = var.flow_logs_retention_days >= 14 && var.flow_logs_retention_days <= 30
    error_message = "flow_logs_retention_days must be between 14 and 30 (MASTERPLAN.md §2's documented range)."
  }
}

variable "flow_logs_bucket_force_destroy" {
  description = "Whether the Flow Logs S3 bucket can be destroyed even if it still contains objects. Sandbox/testing only — never true in a real environment, same reasoning as account-foundation's state_bucket_force_destroy."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to every resource this module creates, merged with the AWS provider's own default_tags (see terragrunt/root.hcl)."
  type        = map(string)
  default     = {}
}
