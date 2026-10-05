# ecr-repositories

Creates one or more ECR repositories via [`terraform-aws-modules/ecr/aws`](https://github.com/terraform-aws-modules/terraform-aws-ecr) (`~> 3.2`). Account/region-level infrastructure with no dependency on `eks-cluster` — see MASTERPLAN.md §2, Fase 2.

## What this module does

- **`for_each` over a list of real app-repo names** — not placeholders. The upstream `terraform-aws-modules/ecr/aws` module creates exactly one repository per call (confirmed against its own `variables.tf`: a singular `repository_name`, resource `count` capped at 1, no native multi-repo mechanism) — this module's own `for_each`, one module instance per repo name, is what makes a list of repos possible. See ADR-000: this is the only place that decides which apps have an ECR repository in a given account/region/environment.
- **Optional `ecr_namespaces`**, replicating TicketSocket v1's real pattern (one AWS account shared across every environment, environment encoded as a path prefix — `aws-ecr.tf`'s `${namespace}${repo_name}`). Empty (default) = this project's own default model (ADR-002: one account per environment, so no prefix needed). Populated = the full cartesian product of namespaces × repo names (`setproduct()`), one repository per pair. Keys are the full repository name strings (`"dev/ts-admin-tickets"`), never list indices — verified directly that adding a namespace or repo to an already-applied set only creates the new entries, with zero diff on the existing ones.
- **Lifecycle policy**: "keep last N images" (default N=10, TicketSocket v1's own default), `tagStatus: "any"`. Built as a raw JSON string via `jsonencode()` — the upstream module's `repository_lifecycle_policy` variable takes JSON directly, there's no structured/typed lifecycle variable — following AWS's own documented ECR lifecycle policy schema (`rules[].selection.countType = "imageCountMoreThan"`, `countNumber` as a JSON number).
- **`repository_force_delete`** — same reasoning as `account-foundation`'s `state_bucket_force_destroy`: lets sandbox/testing `destroy` a repo without manually emptying it first.
- `repository_urls`/`repository_arns` outputs, keyed by **the repository's full name** (namespace/path included, if `ecr_namespaces` is in use) — not a bare app name. Each app-repo's own GitHub Action reads its own full repo identity's key to get the URL to `docker push` to, with nothing to parse or guess.

## What this module does NOT do

- It does not control what gets pushed into a repository. Terraform owns the ECR repository resource itself (ADR-000); each app-repo's own CI/CD pushes images, entirely outside this project's scope.
- It does not create an EKS cluster or any compute (`terraform/modules/eks-cluster`, Phase 3).
- It does not decide which apps exist — `var.repository_names` is the single source of truth for that, driven by `env.hcl`, not by this module.

## Inputs

See [`variables.tf`](./variables.tf). `repository_names` is required, everything else has a sandbox-reasonable default — `image_tag_mutability` defaults to `IMMUTABLE` (the generally-recommended setting, since a mutable tag can be silently repointed to different image content after the fact).

## Outputs

See [`outputs.tf`](./outputs.tf). Both outputs are maps — see "What this module does" above for the keying convention.

## Example

```hcl
module "ecr_repositories" {
  source = "../../modules/ecr-repositories"

  repository_names = [
    "ts-admin-tickets",
    "front/ts-admin-seated-ticketing",
  ]

  # ecr_namespaces left empty — this account is per-environment (ADR-002 default)

  lifecycle_policy_keep_last_n = 10

  tags = {
    ManagedBy = "terraform"
  }
}
```

## A real limitation found validating this against Floci: `IMMUTABLE` and the first-ever push

Validating the ROADMAP's acceptance criterion ("a real `docker push` succeeds") against [Floci](../../../local/README.md) surfaced a real bug in Floci's ECR emulation, not in this module: a repository created with `image_tag_mutability = "IMMUTABLE"` rejects the **very first** `docker push` of any tag — including a tag that has never existed in that repository before — with `"tag ... already exists and cannot be overwritten"`. Reproduced three separate times (a never-used tag on a freshly-applied repo, a different tag on the same repo, a first push to a second, completely empty repository) to rule out digest caching or a stale test artifact. Switching the same repository to `MUTABLE` and re-pushing the identical image succeeded immediately (`digest: sha256:...`, no error).

**This does not change this module's design or default** — `IMMUTABLE` stays the default, since it's the generally-recommended setting and the bug is specific to Floci's emulation, not to this module or to real AWS ECR. The acceptance criterion itself was validated with `MUTABLE` instead (confirming `repository_url`/permissions are genuinely consumable from an external `docker push`, which is what the criterion is actually testing) — real-AWS validation of `IMMUTABLE` specifically remains deferred along with the rest of this project's real-AWS-account validation (see ROADMAP.md Step 13, same redefined-scope approach as Step 7).

## Standalone apply/destroy — what does and doesn't clean up

Testing this module in isolation with `terraform apply` followed by `terraform destroy` leaves the account clean — confirmed against Floci (`Resources: 6 added` / `6 destroyed`, both the flat and the namespaced cases, no residue). `repository_force_delete = true` in the example `.tfvars` is required for a clean `destroy` once a repo has images in it — without it, `destroy` fails on a non-empty repository, same reasoning as `account-foundation`'s `state_bucket_force_destroy`.

## Two ways this module gets its input values — don't confuse them

**1. Standalone testing, via `terraform.tfvars.example`.** Copy it to `terraform.tfvars` (gitignored) and run `terraform plan -var-file=terraform.tfvars` directly from this directory. Not how it's invoked in the real project. Either against real AWS, or — at zero cost, with no account needed — against [Floci](../../../local/README.md), this project's local AWS emulator.

**Delete `terraform.tfvars` when you're done testing standalone** — same reasoning as every other module in this project: it gets copied into `.terragrunt-cache` with the rest of this directory whenever a unit uses this module as `source`, and Terraform loads it automatically.

**2. The real project, via Terragrunt's `env.hcl` pattern — this is what actually runs.** `terragrunt/live/<account>/<region>/<env>/ecr/terragrunt.hcl` reads `repository_names` (and `ecr_namespaces`, if used) from that environment's shared `env.hcl`, same as every other unit — adding a new app's repo is a one-line `env.hcl` change, not a module edit. See [`terragrunt/README.md`](../../../terragrunt/README.md) and [`docs/architecture.md`](../../../docs/architecture.md)'s note on who can merge that kind of change.

If you're only working inside `terraform/modules/ecr-repositories/`, use option 1. If you're deploying a real environment, option 2 is the only path that matters.
