# github-oidc

Creates the GitHub Actions OIDC identity provider in AWS IAM, and the two roles GitHub Actions assumes for this project's CI: `plan` (read-only, any ref) and `apply` (gated, main branch only). No static AWS access keys anywhere — every CI run authenticates via OIDC token exchange.

This module owns identity only. It does **not** grant these roles any permissions on the Terraform state backend — that's [`terraform/modules/account-foundation`](../account-foundation/README.md), which accepts this module's `plan_role_arn`/`apply_role_arn` outputs as its `plan_role_trusted_principal_arns`/`apply_role_trusted_principal_arns` inputs. The two modules are split deliberately: this one answers "who is GitHub Actions, as far as AWS IAM is concerned," `account-foundation` answers "what can the Terraform state's plan/apply roles actually do." Neither module has to know the other's internals — only the role ARNs cross the boundary.

## What this module does

- Creates one `aws_iam_openid_connect_provider` for `https://token.actions.githubusercontent.com` (unless `create_oidc_provider = false`, in which case it uses `existing_oidc_provider_arn` instead — there can only be one OIDC provider per URL per AWS account, so a second account trying to create its own would conflict if, say, both live under the same Organization with a shared trust setup — not this project's situation today, but the toggle exists for that case).
- `thumbprint_list` is intentionally left empty. AWS validates GitHub's OIDC endpoint against its own library of trusted root CAs for GitHub specifically (and several other well-known providers) — it does not use a thumbprint you supply for these. Verified against AWS's IAM documentation and the current `hashicorp/aws` provider docs; this is not a placeholder to fill in later, it's the correct, current value.
- Creates the `plan` role, trust policy scoped to `repo:<github_repository>:*` (any ref — branches, PRs, tags) via `token.actions.githubusercontent.com:sub`, `StringLike`. Broad on purpose: `account-foundation`'s plan-role IAM policy is already read-only + lock-file-write-only, so restricting *which ref* can assume it adds little beyond what the destination permissions already enforce.
- Creates the `apply` role, trust policy scoped to `repo:<github_repository>:ref:refs/heads/main` only, `StringLike`. Narrow on purpose — apply has real read/write access to Terraform state; it must never be assumable from a pull request branch or any ref other than the one CI's gated apply workflow actually runs from.
- Both trust policies also require `token.actions.githubusercontent.com:aud = sts.amazonaws.com`, per GitHub's own OIDC guidance — prevents token confusion with other audiences.

## What this module does NOT do

- It does not grant these roles any AWS permissions beyond the ability to be assumed. Permissions come entirely from `account-foundation` (or any other module that later accepts these roles' ARNs as trusted principals).
- It does not create a `developer-readonly` role — that one is assumed via SSO, not OIDC, so it's created directly by `account-foundation` from `developer_readonly_trusted_principal_arns` (a human's SSO permission-set ARN, not a GitHub Actions role).
- It does not configure the GitHub side (the `.github/workflows/*.yml` files that actually call `aws-actions/configure-aws-credentials` with these role ARNs) — that's a later step (see `ROADMAP.md`, Step 5).

## Prerequisites

Same account-level prerequisites as `account-foundation` — see [its README](../account-foundation/README.md#prerequisites--what-must-already-exist-in-aws-before-running-this-module). This module needs bootstrap credentials for its first apply, same as any other module in this account, before any OIDC-based role exists to hand CI going forward.

## Inputs / Outputs

See [`variables.tf`](./variables.tf) and [`outputs.tf`](./outputs.tf). The one required input is `github_repository` (`"org/repo"` format) — every trust policy is scoped to it, so nothing else can assume these roles regardless of what other AWS-side permissions might exist.

## Two ways this module gets its input values — don't confuse them

Same pattern as [`account-foundation`](../account-foundation/README.md#two-ways-this-module-gets-its-input-values--dont-confuse-them):

**1. Standalone testing, via `terraform.tfvars.example`.** Copy it to `terraform.tfvars` (gitignored) and run `terraform plan -var-file=terraform.tfvars` directly from this directory. Useful for iterating on this module in isolation. Not how it's invoked in the real project.

**2. The real project, via Terragrunt's `env.hcl` pattern.** `terragrunt/live/<account>/<region>/<env>/github-oidc/terragrunt.hcl` reads `github_repository` from the shared `env.hcl` for that environment — same file every other unit in that environment reads. See `terragrunt/README.md`.

If you're only working inside `terraform/modules/github-oidc/`, use option 1. If you're deploying a real environment, option 2 is the only path that matters.

## How this connects to account-foundation, in practice

This is wired via Terragrunt's `dependency` block, not by hand — see `terragrunt/live/<account>/<region>/<env>/foundation/terragrunt.hcl`, which reads `github-oidc`'s `plan_role_arn`/`apply_role_arn` outputs directly. `mock_outputs` let `foundation` plan/render even before `github-oidc` has ever been applied; the real dependency order is `github-oidc` first, `foundation` second — see `terragrunt/README.md` for the full pattern.
