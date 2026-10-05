# AWS EKS Base v2

A reusable AWS EKS platform foundation.

**Terraform creates the platform. Terragrunt composes the environment. GitOps operates Kubernetes.**

This is not another EKS Terraform module, and it is not a fork or an incremental patch of any existing project. It is a ground-up architecture, built from scratch around one governing rule: no resource has two authoritative owners. Terraform owns AWS infrastructure. Terragrunt owns environment composition. GitOps owns everything that runs inside Kubernetes, from the moment the GitOps controller itself comes online.

## Where to start

- **[ROADMAP.md](./ROADMAP.md)** — the implementation checklist. Start here to see what's built, what's in progress, and what's next.
- **[MASTERPLAN.md](./MASTERPLAN.md)** — the executable plan: phase-by-phase scope, deliverables, acceptance criteria, repository tree, dependency graph, cost architecture, disaster recovery posture.
- **[ADR.md](./ADR.md)** — the architecture decision records. Nine decisions (000–008), each with context, alternatives considered, and consequences. Start with ADR-000 (ownership boundaries) — everything else is checked against it.
- **[ASSESSMENT.md](./ASSESSMENT.md)** — the Phase 0 assessment that shaped this design: current-state findings and the reasoning behind each decision.
- **[docs/architecture.md](./docs/architecture.md)** — operational runbooks and documented trade-offs (state recovery, access-model notes) that don't fit a module's own README or the step-by-step checklist. Grows incrementally, one phase at a time.

> Note: `ADR.md`, `ASSESSMENT.md`, `MASTERPLAN.md`, and `ROADMAP.md` are intentionally excluded from version control, indefinitely — not a temporary state until some milestone (see `.gitignore`). They exist only as the author's local living design/tracking documents; nothing about the plan they describe lives in this repository's git history, only the actual code it produces.

## Repository layout

```
aws-eks-base-v2/
├── terraform/
│   ├── modules/        # Reusable building blocks (account-foundation, github-oidc, network, ecr-repositories, eks-cluster, gitops-bootstrap, ...) — invoked directly by a single Terragrunt unit when one module is enough
│   └── layers/          # Reserved for when a unit needs to compose more than one module into one apply — not yet used; see ROADMAP.md's Phase 2 note
├── terragrunt/
│   ├── root.hcl         # Root config: backend + provider generation
│   ├── _accounts/       # Account-level configuration (account.hcl per AWS account)
│   └── live/            # The actual environment tree: <account>/<region>/<env>/<unit>
├── gitops/               # Reconciled by Argo CD — never touched by `terraform apply`
│   ├── bootstrap/        # App-of-Apps root
│   ├── clusters/         # Per-cluster overlays
│   └── apps/              # Platform addons (Karpenter, cert-manager, ESO, ...), one directory each
├── docs/
│   ├── architecture.md    # Operational runbooks and documented trade-offs — grows incrementally, one phase at a time
│   └── optional-patterns/ # Documented but not shipped: patterns for things deliberately kept out of core
├── .github/workflows/    # CI: terraform-plan.yml (OIDC + fmt/validate/tflint/trivy + GitOps boundary gate), terraform-apply.yml (OIDC, gated by GitHub Environment)
└── local/                # Local dev stack (Floci, a free AWS emulator) — investigation/testing aid, not part of the deployable architecture
```

See [MASTERPLAN.md §3](./MASTERPLAN.md) for the full annotated tree and the reasoning behind it.

## The core rule

Terraform installs exactly one Kubernetes workload, ever: the GitOps controller. Nothing else — not a metrics-server "because it's tiny," not a CRD "because it's small." Everything else that runs on the cluster is reconciled by GitOps, with zero Terraform awareness of its existence. This boundary is enforced in CI, not just documented — see ADR-001.

## Toolchain

Terraform and Terragrunt versions are pinned per-project via [`tfenv`](https://github.com/tfutils/tfenv) and [`tgenv`](https://github.com/cunymatthieu/tgenv) — see `.terraform-version` and `.terragrunt-version` at the repo root. Run `tfenv install` / `tgenv install` once; both tools pick up the pinned version automatically from any directory inside this repo afterward.

## Running this project (Terragrunt)

Every unit lives under `terragrunt/live/<account>/<region>/<env>/<unit>/`. A unit's inputs come from exactly two files: `terragrunt/_accounts/<account>/account.hcl` (account-level data — account ID, whether it's the AWS Organizations payer account) and `terragrunt/live/<account>/<region>/<env>/env.hcl` (everything else for that environment — region, cost-allocation tags, and every module input for every unit in that environment). Change a value once, in `env.hcl`; every unit in that environment picks it up. See ADR-002 for why the hierarchy is structured this way.

**Before the first apply in a new account**, read `terraform/modules/account-foundation/README.md`'s Prerequisites section — an AWS account and bootstrap SSO credentials need to exist first; neither is created by this project's Terraform. The GitHub Actions OIDC provider and the roles it assumes ARE created by this project (`terraform/modules/github-oidc/`), but that module has to apply before `account-foundation` — see `terragrunt/README.md`'s "Dependencies between units" section.

**`foundation`'s own very first `apply` in a new account needs a different procedure than the plain `terragrunt apply` below** — it creates the S3 bucket its own state is meant to live in, which is a real self-reference problem, not a one-off quirk of this account. See `terraform/modules/account-foundation/README.md`'s "The first-ever apply in a real account" section before running anything against a brand-new account — skipping it produces a `BucketAlreadyExists` error (with `--backend-bootstrap`) or a hanging prompt (with a bare `-migrate-state`), not a working apply.

```sh
# From inside a unit directory, e.g. terragrunt/live/nonprod/us-east-1/dev/foundation/

terragrunt render --format json    # inspect the fully-resolved config (inputs, backend, provider) without touching AWS
terragrunt plan                    # requires valid AWS credentials for the target account
terragrunt apply
terragrunt destroy
```

`terragrunt render` is worth running first, especially in a new environment — it resolves every `include`/`read_terragrunt_config` call and prints the exact backend config, provider block, and module inputs Terragrunt would use, with zero risk (no AWS credentials needed, nothing is created).

**KMS note**: destroying and immediately re-applying `foundation` in the same account is safe — AWS frees a deleted KMS alias for reuse immediately, even while the key it used to point to sits in `PendingDeletion` for its full deletion window. See `terraform/modules/account-foundation/README.md` for the sourced explanation; this applies identically whether the module is run standalone or through Terragrunt, since it's AWS KMS behavior, not something either tool controls.

Formatting: `terragrunt hcl format` (from the `terragrunt/` directory) formats every `.hcl` file in the tree; `terragrunt hcl format --check --diff` verifies formatting without changing anything (used in CI).

## Local development

[`local/`](./local/) runs [Floci](https://github.com/floci-io/floci), a free local AWS emulator, via Docker Compose — a way to run real `terragrunt plan`/`apply` against every unit in this project (including EKS, once `eks-cluster` exists) with zero AWS cost and zero risk to this project's one real AWS account. See [local/README.md](./local/README.md) for setup, and for two real issues this stack caught early: a broken module `source` path, and a circular state-bucket bootstrap dependency resolved by giving `github-oidc` a permanent local Terraform backend.

## Continuous integration

Two workflows in `.github/workflows/`, both authenticating to AWS via GitHub Actions OIDC (`terraform/modules/github-oidc`) — no static AWS access keys anywhere in this repo.

- **`terraform-plan.yml`** — triggered manually (`workflow_dispatch`) for now rather than automatically on every pull request, until there's real confidence in the pipeline against a real AWS account (the original `pull_request` trigger is kept commented out in the file for when it's re-enabled). First job (`boundary-check`) is a hard gate enforcing ADR-001: it fails the run outright if any `helm_release`, `kubectl_manifest`, or non-allowlisted `kubernetes_*` resource appears anywhere in `terraform/` outside `terraform/modules/gitops-bootstrap/`. The second job runs `terraform fmt -check`, `terragrunt hcl format --check`, `tflint`, a Trivy IaC config scan (`aquasecurity/trivy-action` — Trivy replaces tfsec here; tfsec has been in maintenance-only mode since its rules were absorbed into Trivy in 2023), and `terragrunt plan` for every unit, authenticated with the **plan** role.
- **`terraform-apply.yml`** — also triggered manually (`workflow_dispatch`) for now rather than automatically on push to `main`, for the same reason (the original trigger is likewise kept commented out). Gated behind a GitHub Environment named `production` requiring manual approval — nothing applies unattended. Authenticated with the **apply** role, which by default only trusts `main`-branch workflow runs (see `terraform/modules/github-oidc`'s `apply_role_ref_condition`). Applies units one at a time, in dependency order (`github-oidc` before `foundation`).

**Repository configuration required before either workflow can run** (one-time, manual — not created by this project's Terraform, to avoid a chicken-and-egg bootstrap problem):
- Repository variables (Settings → Secrets and variables → Actions → Variables): `PLAN_ROLE_ARN` and `APPLY_ROLE_ARN`, set to the `plan_role_arn`/`apply_role_arn` outputs of the `github-oidc` unit once it's been applied at least once via a human with SSO credentials (see `terraform/modules/github-oidc/README.md`).
- A `production` GitHub Environment (Settings → Environments) with at least one required reviewer, so `terraform-apply.yml` pauses for approval instead of applying unattended on every merge.

## Secret scanning

[`gitleaks`](https://github.com/gitleaks/gitleaks) runs on every commit via `.pre-commit-config.yaml`, scanning staged changes for hardcoded credentials before they reach git history. Added after auditing a real, multi-year production fork of this project turned up several real hardcoded credentials (MongoDB Atlas creds, an SSH private key, AWS key pairs) committed despite the correct pattern (Secrets Manager + External Secrets Operator) already existing in the same codebase — having the right pattern available doesn't stop it from being bypassed under pressure; an automated gate does.

```sh
brew install pre-commit   # one-time, per machine
pre-commit install        # one-time, per clone — wires the git hook
```

No `.gitleaks.toml` yet — gitleaks' built-in default ruleset runs with zero configuration. This is the local, pre-commit-only layer; a hard CI-level gate (blocking merges outright, plus a one-time full-history scan) is a separate, later addition — see `MASTERPLAN.md`'s Phase 9 scope.

## Author

Jack Pelorus ([@jacksmartv](https://github.com/jacksmartv))

## License

[MIT](./LICENSE)
