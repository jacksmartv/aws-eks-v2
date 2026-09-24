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
│   ├── terragrunt.hcl   # Root config: backend + provider generation
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

## Author

Jack Pelorus ([@jacksmartv](https://github.com/jacksmartv))

## License

[MIT](./LICENSE)
