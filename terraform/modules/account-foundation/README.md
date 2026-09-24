# account-foundation

The first Terraform module in the account → region → environment → unit hierarchy (ADR-002). Provisions the account-wide resources every other unit depends on: the Terraform state backend itself, KMS customer-managed keys, and the three state-access IAM roles.

This module runs **once per AWS account**, not once per environment — see MASTERPLAN.md §1.1 for why state isolation is done by S3 key prefix within one bucket, not by a separate bucket per environment.

## Prerequisites — what must already exist in AWS before running this module

This module creates the state backend itself, which means the very first `terraform apply` for a new account has to run **without** the S3 backend this module is about to create (a classic bootstrap chicken-and-egg problem). The following must exist beforehand, none of it created by this module:

1. **An AWS account.** Sandbox, nonprod, or prod — this module does not create AWS Organizations accounts, it only configures resources inside one that already exists.
2. **Bootstrap credentials with account-admin-equivalent permissions**, used once, locally or from a one-off CI run, to apply this module for the very first time (before the state bucket and the three state-access roles exist, nothing else can apply changes to this account). In practice this is typically an AWS IAM Identity Center (SSO) permission set with `AdministratorAccess`, assumed manually for the initial apply — **not** a long-lived IAM user. Once this module's outputs exist, all subsequent applies in this account go through `apply-role` instead; the bootstrap credential is not needed again unless the state bucket itself needs to be rebuilt from scratch.
3. **A GitHub Actions OIDC identity provider registered in this AWS account's IAM** (`https://token.actions.githubusercontent.com`), plus the actual IAM roles that assume it (one for plan, one for apply — typically scoped by GitHub repo/branch condition in their trust policy). **This module does not create the OIDC provider or those roles** — it only creates the roles that `plan_role_trusted_principal_arns`/`apply_role_trusted_principal_arns` name as trusted principals, i.e. it grants state-bucket permissions to roles that must already exist. If the OIDC provider or the GitHub-side roles aren't set up yet, those variables have nothing valid to point at. Setting up the OIDC provider itself is out of scope for `account-foundation` — see `docs/architecture.md` (added in a later phase) for the reference pattern, or provision it manually/via a separate bootstrap module before wiring CI.
4. **If `sso_instance_arn` is going to be used**: an AWS IAM Identity Center instance already enabled for the AWS Organization this account belongs to, with at least one permission set an operator can assume for `developer_readonly_trusted_principal_arns`. This module does not enable Identity Center, create permission sets, or assign users — it only accepts an existing instance's ARN and existing principal ARNs as inputs.

**Practical bootstrap order for a brand-new account:**
```
1. Account exists (AWS Organizations or standalone)
2. SSO admin permission set assumable in the account (manual, one-time)
3. terraform apply (with the SSO admin session's temporary credentials, no backend config yet — local state)
4. Migrate state into the bucket this module just created (terraform init -migrate-state, now pointed at the new backend)
5. Set up the GitHub OIDC provider + plan/apply roles (separately, not by this module)
6. Pass those roles' ARNs into plan_role_trusted_principal_arns / apply_role_trusted_principal_arns
7. terraform apply again — CI can now plan/apply this account without the bootstrap credential
```

## What this module does

- Creates the S3 bucket used as the Terraform state backend for the entire account, with versioning and SSE-KMS encryption enabled, and public access fully blocked.
- Creates two KMS customer-managed keys: one dedicated to encrypting the state bucket, one set as the account's default EBS encryption key (reused later by the EKS cluster module for node volume encryption). Each key's policy grants the AWS service that actually needs it (`s3.amazonaws.com` for the state key, `ec2.amazonaws.com` for the EBS key) an explicit, scoped grant — not an implicit reliance on the root-account statement.
- Enables EBS encryption-by-default at the account level, pointed at the account's EBS KMS key.
- Creates up to three IAM roles for Terraform state access — `plan`, `apply`, `developer-readonly` — each only if its corresponding trusted-principal variable is non-empty. See [MASTERPLAN.md §1.1](../../../MASTERPLAN.md) for the full reasoning behind this three-role split; in short:
  - **plan-role**: read-only on state, write access limited to the S3 native lock file. Assumed by CI on every pull request.
  - **apply-role**: full read/write on state. Assumed only by the gated `terraform-apply.yml` CI workflow, never by a human.
  - **developer-readonly**: identical scope to plan-role, for local debugging. No one — not even an administrator — applies from a local machine with this module's roles.

## What this module does NOT do

- It does not create a VPC or any networking (`terraform/modules/network`, a separate module, layered in Phase 2).
- It does not create an EKS cluster (`terraform/modules/eks-cluster`, Phase 3).
- It does not configure AWS IAM Identity Center (SSO) itself — `sso_instance_arn` is a placeholder variable for referencing an SSO instance that exists elsewhere; this module does not provision one.
- It does not create the GitHub Actions OIDC identity provider or the GitHub-side roles that assume it — see Prerequisites above. It only grants state-bucket/KMS permissions to role ARNs that are assumed to already exist.
- It does not enable S3 native state locking on any backend — that's configured per-unit, in each Terragrunt `remote_state` block, via `use_lockfile = true`. This module only creates the bucket those units point at.
- It does not manage DynamoDB. State locking in this project is S3-native (Terraform ≥ 1.11) — no lock table exists anywhere.

## Inputs

See [`variables.tf`](./variables.tf) for the full list with descriptions. The three `*_trusted_principal_arns` variables default to an empty list, meaning no role is created by default — a consuming unit must explicitly pass at least the OIDC role ARN it wants to grant plan/apply/readonly access to.

## Outputs

See [`outputs.tf`](./outputs.tf). Notably `state_bucket_name` and `state_kms_key_arn`, which every other unit's Terragrunt backend configuration needs, and `ebs_kms_key_arn`, which the `eks-cluster` module reuses for node volume encryption.

## Example

```hcl
module "account_foundation" {
  source = "../../modules/account-foundation"

  account_name = "nonprod"

  plan_role_trusted_principal_arns = [
    "arn:aws:iam::123456789012:role/github-actions-oidc-plan",
  ]
  apply_role_trusted_principal_arns = [
    "arn:aws:iam::123456789012:role/github-actions-oidc-apply",
  ]

  kms_key_administrator_arns = [
    "arn:aws:iam::123456789012:role/platform-admin",
  ]
}
```

## Standalone apply/destroy — what does and doesn't clean up

Testing this module in isolation with `terraform apply` followed by `terraform destroy` does **not** leave the account perfectly clean, even with `terraform.tfvars.example`'s defaults:

- **S3 state bucket**: destroys cleanly. `terraform.tfvars.example` sets `state_bucket_force_destroy = true`, so the bucket is removed even though it holds the state file itself — without that flag, `destroy` would fail on a non-empty bucket.
- **IAM roles**: destroy cleanly, no residue. (The example tfvars leave all three `*_trusted_principal_arns` empty, so none of the three roles are even created in a default standalone test.)
- **EBS encryption-by-default / default KMS key setting**: account-level configuration, reverts cleanly.
- **The two KMS keys (`state`, `ebs`) do NOT disappear immediately.** AWS enforces a mandatory waiting period before actually deleting a KMS key — `terraform destroy` only schedules deletion; the key stays in `PendingDeletion` state for `kms_deletion_window_in_days` (the example tfvars use `7`, AWS's minimum), and it keeps counting toward your account's KMS key limits and (negligibly) billing until then. **This does NOT block re-running `terraform apply` with the same `account_name` right after a `destroy`**, and it does not need a manual workaround — verified against AWS's own KMS documentation: `terraform destroy` deletes the `aws_kms_alias` resource before scheduling the key's deletion (normal reverse-dependency order, since the alias depends on the key), and AWS treats an alias name as immediately reusable the moment `DeleteAlias` succeeds, regardless of what state the key it used to point to is in. A fresh `apply` right after `destroy` creates a new key and successfully claims the same alias name — the old, pending-deletion key is a separate, orphaned resource sitting quietly in the background for the rest of its deletion window, not something blocking the new one.

## Two ways this module gets its input values — don't confuse them

**1. Standalone testing, via `terraform.tfvars.example`.** Copy it to `terraform.tfvars` (gitignored) and run `terraform plan -var-file=terraform.tfvars` directly from this directory. This is for quickly testing or iterating on the module in isolation, without the rest of the Terragrunt tree existing yet. It is **not** how this module is invoked in the real project.

**2. The real project, via Terragrunt's `env.hcl` pattern — this is what actually runs.** Every unit in a given environment (`foundation`, `network`, `ecr`, `eks-cluster`, `gitops-bootstrap`) reads its input values from a single shared `env.hcl` file for that environment:

```
terragrunt/
├── root.hcl                                 # root: backend + provider generation, default_tags
├── _accounts/
│   └── nonprod/account.hcl                 # account_id, account_name
└── live/nonprod/us-east-1/dev/
    ├── env.hcl                             # the one file that defines this environment's values
    └── foundation/terragrunt.hcl           # reads env.hcl + account.hcl, invokes this module
```

`env.hcl` holds the same kind of values as `terraform.tfvars.example` (account name, KMS admin ARNs, role trust principals, etc.), but scoped to one environment and shared by every unit in it — change it once, every unit in that environment picks it up. Nothing here is duplicated per-module the way a per-module `.tfvars` file would be. See [`terragrunt/README.md`](../../../terragrunt/README.md) for the full pattern.

If you're only working inside `terraform/modules/account-foundation/`, use option 1. If you're deploying a real environment, option 2 is the only path that matters — the `.tfvars.example` file is a development convenience, not a second supported way to run this project.
