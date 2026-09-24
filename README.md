# AWS EKS Base v2

A reusable AWS EKS platform foundation.

**Terraform creates the platform. Terragrunt composes the environment. GitOps operates Kubernetes.**

This is not another EKS Terraform module, and it is not a fork or an incremental patch of any existing project. It is a ground-up architecture, built from scratch around one governing rule: no resource has two authoritative owners. Terraform owns AWS infrastructure. Terragrunt owns environment composition. GitOps owns everything that runs inside Kubernetes, from the moment the GitOps controller itself comes online.

## Where to start

- **[ROADMAP.md](./ROADMAP.md)** — the implementation checklist. Start here to see what's built, what's in progress, and what's next.
- **[MASTERPLAN.md](./MASTERPLAN.md)** — the executable plan: phase-by-phase scope, deliverables, acceptance criteria, repository tree, dependency graph, cost architecture, disaster recovery posture.
- **[ADR.md](./ADR.md)** — the architecture decision records. Nine decisions (000–008), each with context, alternatives considered, and consequences. Start with ADR-000 (ownership boundaries) — everything else is checked against it.
- **[ASSESSMENT.md](./ASSESSMENT.md)** — the Phase 0 assessment that shaped this design: current-state findings and the reasoning behind each decision.

> Note: `ADR.md`, `ASSESSMENT.md`, `MASTERPLAN.md`, and `ROADMAP.md` are intentionally excluded from version control until Phase 1 is validated end-to-end (see `ROADMAP.md`, Step 8, and `.gitignore`). They exist locally as living design documents while implementation is in progress.

## Repository layout

```
aws-eks-base-v2/
├── terraform/
│   ├── modules/        # Reusable building blocks (account-foundation, eks-cluster, gitops-bootstrap, ...)
│   └── layers/          # Per-account/region/env Terraform roots, one per Terragrunt unit
├── terragrunt/
│   ├── root.hcl         # Root config: backend + provider generation
│   ├── _accounts/       # Account-level configuration (account.hcl per AWS account)
│   └── live/            # The actual environment tree: <account>/<region>/<env>/<unit>
├── gitops/               # Reconciled by Argo CD — never touched by `terraform apply`
│   ├── bootstrap/        # App-of-Apps root
│   ├── clusters/         # Per-cluster overlays
│   └── apps/              # Platform addons (Karpenter, cert-manager, ESO, ...), one directory each
├── docs/
│   └── optional-patterns/ # Documented but not shipped: patterns for things deliberately kept out of core
└── .github/workflows/    # CI: plan/apply via OIDC, policy scanning
```

See [MASTERPLAN.md §3](./MASTERPLAN.md) for the full annotated tree and the reasoning behind it.

## The core rule

Terraform installs exactly one Kubernetes workload, ever: the GitOps controller. Nothing else — not a metrics-server "because it's tiny," not a CRD "because it's small." Everything else that runs on the cluster is reconciled by GitOps, with zero Terraform awareness of its existence. This boundary is enforced in CI, not just documented — see ADR-001.

## Toolchain

Terraform and Terragrunt versions are pinned per-project via [`tfenv`](https://github.com/tfutils/tfenv) and [`tgenv`](https://github.com/cunymatthieu/tgenv) — see `.terraform-version` and `.terragrunt-version` at the repo root. Run `tfenv install` / `tgenv install` once; both tools pick up the pinned version automatically from any directory inside this repo afterward.

## Running this project (Terragrunt)

Every unit lives under `terragrunt/live/<account>/<region>/<env>/<unit>/`. A unit's inputs come from exactly two files: `terragrunt/_accounts/<account>/account.hcl` (account-level data — account ID, whether it's the AWS Organizations payer account) and `terragrunt/live/<account>/<region>/<env>/env.hcl` (everything else for that environment — region, cost-allocation tags, and every module input for every unit in that environment). Change a value once, in `env.hcl`; every unit in that environment picks it up. See ADR-002 for why the hierarchy is structured this way.

**Before the first apply in a new account**, read `terraform/modules/account-foundation/README.md`'s Prerequisites section — an AWS account, bootstrap SSO credentials, and (eventually) a GitHub Actions OIDC provider all need to exist first; none of them are created by this project's Terraform.

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

## Author

Jack Pelorus ([@jacksmartv](https://github.com/jacksmartv))

## License

[MIT](./LICENSE)
