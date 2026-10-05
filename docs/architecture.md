# Architecture notes

This file holds operational runbooks and documented trade-offs that don't fit naturally into a module's own `README.md` or into `ROADMAP.md`'s step-by-step checklist — things a future operator needs once something has already gone wrong, or a convention that needs to be named explicitly so nobody re-decides it differently later.

It grows incrementally, one phase at a time, alongside the actual implementation — not written in one pass up front. See `ROADMAP.md`'s own step-by-step log for when each section below was added and why.

## Terraform state recovery

**Ownership model** (established in `account-foundation`, see [ROADMAP.md](../ROADMAP.md) Steps 2–4): one S3 bucket per AWS account (not per environment), isolated by key prefix `<region>/<env>/<unit>/terraform.tfstate` within that bucket. Three IAM roles — `plan` (read-only, plus lock-file write), `apply` (full read/write, gated behind `terraform-apply.yml`'s manual `workflow_dispatch` trigger and a GitHub Environment approval), `developer-readonly` (same scope as `plan`, for local debugging — nobody applies from a laptop, not even an admin). All three assumed via OIDC/SSO, never static credentials.

**Locking:** S3 native locking (`use_lockfile = true`, Terraform ≥1.11) — no DynamoDB table anywhere in this project.

**Recovery runbook, if a lock or a state file is ever actually corrupted:**

1. **Confirm there is no `apply` genuinely in progress before touching anything.** A held lock is not automatically an orphaned lock — check whether a `terraform-apply.yml` run is actually still executing (GitHub Actions run history) before assuming it's safe to unlock.
2. **`terraform force-unlock` only from the apply-role.** Never from `plan` or `developer-readonly` — those roles don't have write access to the state object itself, only to the lock file, and force-unlocking with the wrong role is a symptom that the wrong credentials are being used for a write operation in the first place.
3. **A corrupted state file is recovered by restoring the bucket's previous object version, not by rebuilding from scratch.** The state bucket has versioning enabled specifically for this — `aws s3api list-object-versions` on the state key, then `aws s3api copy-object` (or a Terraform-aware restore) to promote the last known-good version back to current. Reconstructing state from `terraform import` is the last resort, not the first move.

## `account-foundation`'s first-ever apply in a new account

See [`terraform/modules/account-foundation/README.md`](../terraform/modules/account-foundation/README.md#the-first-ever-apply-in-a-real-account-a-self-reference-problem-and-how-to-get-past-it) for the full procedure. Short version: this module creates the S3 bucket its own state is supposed to live in, so its very first apply in a new account needs a temporary local backend, then `terragrunt init -migrate-state -force-copy` into the bucket it just created — otherwise `--backend-bootstrap` and the module's own `aws_s3_bucket.state` resource collide (`BucketAlreadyExists`, confirmed against Floci during Phase 2's provider upgrade work). One-time, by-hand, per account — never something CI does.

## ECR repository list — who can add one, and why that's a real question

Added in Phase 2 (`terraform/modules/ecr-repositories/`, see [ROADMAP.md](../ROADMAP.md) Step 12). The list of ECR repositories for a given account/region/environment lives in that environment's `env.hcl` — adding a new app's repository is a small, mechanical PR against that file, not a reason to touch the module itself.

That also means the real access-control question isn't "who can write Terraform" — it's "who can merge a one-line `env.hcl` change." As the number of apps grows, it's plausible (maybe even desirable) that app teams merge their own repo-list additions directly, without needing the platform team to review every single addition. This project doesn't resolve that access question now — there's no concrete need yet, and deciding it prematurely would just be a guess. Revisit explicitly once the number of apps using this project's ECR units makes "every addition goes through the platform team" a real bottleneck, not before.
