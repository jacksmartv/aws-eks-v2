# network

Thin wrapper around [`terraform-aws-modules/vpc/aws`](https://github.com/terraform-aws-modules/terraform-aws-vpc) (`~> 6.0`), provisioning the VPC, subnets, NAT, VPC Flow Logs, and the VPC endpoints every unit in this account/region will run inside of. Account/region-level infrastructure with no dependency on `eks-cluster` — see MASTERPLAN.md §2, Fase 2.

## What this module does

- Creates a VPC with up to 4 subnet tiers: public, private, database, and intra (fully isolated — no NAT/IGW route at all). Each tier is optional (empty list = not created); which tiers you actually use is an `env.hcl` decision, not something this module opinionates about.
- NAT gateway topology is a required variable (`nat_topology`: `"none"` | `"single"` | `"per_az"`) — no silent default, same reasoning as this project's `compute_mode` variable (ADR-003): a real cost/resilience tradeoff shouldn't be hidden behind a module default.
- **VPC Flow Logs, enabled unconditionally**, delivered to an S3 bucket this module creates and owns (`terraform-aws-modules/vpc/aws` does not create that bucket itself — confirmed against its `variables.tf`, `flow_log_destination_arn` expects a caller-owned ARN). Bucket policy uses the exact principal/actions/conditions AWS's own VPC Flow Logs documentation specifies for S3 delivery (`delivery.logs.amazonaws.com`, `s3:PutObject` + `s3:GetBucketAcl`, scoped by `aws:SourceAccount`/`aws:SourceArn`/`s3:x-amz-acl`) — not a generic "S3 write access" guess. Retention is a short, configurable lifecycle rule (14–30 days — MASTERPLAN.md §2: basic connectivity-debugging visibility, not a long-term audit trail), not indefinite storage.
- **S3 gateway endpoint and ECR (API + DKR) interface endpoints**, each independently toggleable (`enable_s3_endpoint`, `enable_ecr_endpoints`, both default `true`) — built via `terraform-aws-modules/vpc/aws`'s own `vpc-endpoints` submodule, not a hand-rolled `aws_vpc_endpoint` resource. A shared security group is created once and attached to every interface endpoint, scoped to HTTPS from inside this VPC's own CIDR only.
- `additional_vpc_endpoints` — an escape hatch for any endpoint this module hasn't been taught an opinion about (DynamoDB, SSM, STS, etc.). Same map shape the `vpc-endpoints` submodule itself expects — each entry's own keys (`service`, `service_type`, `subnet_ids`, `route_table_ids`, `private_dns_enabled`) follow that submodule's interface directly. Merged with the S3/ECR endpoints this module builds from the two booleans above; empty by default.

## What this module does NOT do

- It does not create an EKS cluster or any compute (`terraform/modules/eks-cluster`, Phase 3) — this module only provisions the network those will run inside of.
- It does not create the account's Terraform state backend, KMS keys, or IAM roles — that's `terraform/modules/account-foundation`, which must already exist in this account (same bootstrap-ordering dependency every unit beyond `foundation`/`github-oidc` has).
- It does not create any VPC endpoint beyond S3/ECR unless `additional_vpc_endpoints` is populated — no DynamoDB, SSM, or STS endpoint by default.

## Inputs

See [`variables.tf`](./variables.tf) for the full list with descriptions. `nat_topology` has no default and must be set explicitly per environment — every other variable has a reasonable default for a sandbox.

## Outputs

See [`outputs.tf`](./outputs.tf). Notably `vpc_id` and `private_subnet_ids`, which `eks-cluster` (Phase 3) will need as inputs once that module exists — see ROADMAP.md Step 13 for the explicit cross-check against that module's actual required inputs once Phase 3 starts.

## Example

```hcl
module "network" {
  source = "../../modules/network"

  name       = "nonprod-dev"
  cidr_block = "10.0.0.0/16"
  azs        = ["us-east-1a", "us-east-1b", "us-east-1c"]

  public_subnets   = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
  private_subnets  = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
  database_subnets = ["10.0.20.0/24", "10.0.21.0/24", "10.0.22.0/24"]

  nat_topology = "single"

  tags = {
    ManagedBy = "terraform"
  }
}
```

## Standalone apply/destroy — what does and doesn't clean up

Testing this module in isolation with `terraform apply` followed by `terraform destroy` leaves the account clean — confirmed against Floci (`Resources: 39 added, 0 changed, 0 destroyed` on apply; `Resources: 39 destroyed` on destroy, no residue). Unlike `account-foundation`'s KMS keys, nothing this module creates has a mandatory AWS-enforced waiting period before actual deletion.

**`flow_logs_bucket_force_destroy`** mirrors `account-foundation`'s `state_bucket_force_destroy` — set `true` only in a throwaway sandbox, since it lets `destroy` remove the Flow Logs bucket even while it still holds log objects.

## Two ways this module gets its input values — don't confuse them

**1. Standalone testing, via `terraform.tfvars.example`.** Copy it to `terraform.tfvars` (gitignored) and run `terraform plan -var-file=terraform.tfvars` directly from this directory. Not how it's invoked in the real project. Either against real AWS, or — at zero cost, with no account needed — against [Floci](../../../local/README.md), this project's local AWS emulator.

**Delete `terraform.tfvars` when you're done testing standalone** — same reasoning as every other module in this project: it gets copied into `.terragrunt-cache` with the rest of this directory whenever a unit uses this module as `source`, and Terraform loads it automatically.

**2. The real project, via Terragrunt's `env.hcl` pattern — this is what actually runs.** `terragrunt/live/<account>/<region>/<env>/network/terragrunt.hcl` reads this module's inputs from that environment's shared `env.hcl`, same as every other unit. See [`terragrunt/README.md`](../../../terragrunt/README.md).

If you're only working inside `terraform/modules/network/`, use option 1. If you're deploying a real environment, option 2 is the only path that matters.
