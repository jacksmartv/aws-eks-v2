# Local development stack (Floci)

A free, local AWS emulator ([Floci](https://github.com/floci-io/floci)) to exercise this project's Terraform modules and Terragrunt units against a real `terraform init`/`plan`/`apply` flow — with zero AWS cost and zero risk to the project's one real AWS account. This is a research/investigation aid, not part of the deployable architecture: nothing under `terraform/` or `terragrunt/`'s real units was changed to make this work.

## What is Floci?

An open-source ("always free", MIT) local AWS emulator — the LocalStack-community-edition alternative, since LocalStack's community edition was sunset in March 2026. It emulates the standard AWS API surface, and critically for this project: **S3, IAM, STS, and KMS run in-process**, and **EKS runs with real Docker containers** (a real `k3s` cluster with a live Kubernetes API server per cluster, real OIDC/IRSA end to end). See [floci.io](https://floci.io/floci/) for the full service list.

## Starting the stack

```sh
cd local/
docker compose up -d
```

This starts one container (`floci/floci:latest`) listening on `http://localhost:4566`, with:
- **Persistent storage** (`FLOCI_STORAGE_MODE: persistent`, named volume `aws-eks-v2-floci-data`) — state created while iterating (buckets, IAM roles, KMS keys, EKS clusters) survives `docker compose down`/restarts.
- **A synthetic 12-digit account ID** (`111111111111`) — deliberately distinct from this project's one real AWS account (`184086410155`), so the two can never be confused in a shell history, a pasted ARN, or a screenshot.
- **The Docker socket mounted** — required for Floci's real (non-mock) EKS mode, which starts one `k3s` container per cluster via the Docker API.

Verify it's up:

```sh
curl http://localhost:4566/_floci/health
docker logs aws-eks-v2-floci --tail 20
```

Stop it (keeps the volume, so state persists):

```sh
docker compose down
```

### Resetting the stack

To wipe all emulated state and start clean:

```sh
docker compose down -v   # -v removes the named volume too
```

## Pointing AWS tools at Floci

Copy the env template and source it:

```sh
cp local/.env.example local/.env
set -a && source local/.env && set +a
```

This exports the AWS SDK's own standard environment variables (`AWS_ENDPOINT_URL`, `AWS_ACCESS_KEY_ID`, etc.) — the same variables the `hashicorp/aws` Terraform provider reads natively. **Nothing in `terraform/` or `terragrunt/` was changed** to make this work: no `endpoints {}` block, no hardcoded test credentials anywhere in the real provider generation (`terragrunt/root.hcl`). Unset these variables (a fresh shell) and every unit goes back to talking to real AWS exactly as before.

```sh
aws sts get-caller-identity
# {
#     "UserId": "111111111111",
#     "Account": "111111111111",
#     "Arn": "arn:aws:iam::111111111111:root"
# }
```

## Wiring Terragrunt to this stack

A parallel Terragrunt "account" exists purely for this purpose: `floci-local`, mirroring the exact same `account → region → environment → unit` hierarchy (ADR-002) as the real `nonprod` account —

```
terragrunt/
├── _accounts/
│   ├── nonprod/account.hcl         # the real (eventual) sandbox AWS account
│   └── floci-local/account.hcl     # this local emulator — account_id = "111111111111"
└── live/
    ├── nonprod/us-east-1/dev/      # the real environment tree
    └── floci-local/us-east-1/dev/  # identical units, pointed at Floci via env vars
        ├── env.hcl
        ├── github-oidc/terragrunt.hcl
        └── foundation/terragrunt.hcl
```

No unit's `.hcl` file, and no `terraform/modules/*` module, has any conditional logic distinguishing "real AWS" from "Floci" — the **only** thing that changes which one a `terragrunt` command talks to is whether `local/.env` is sourced in the current shell, and which `live/<account>/...` directory you're running from.

```sh
set -a && source local/.env && set +a

cd terragrunt/live/floci-local/us-east-1/dev/github-oidc/
terragrunt init
terragrunt apply
```

Then `foundation`, which needs `github-oidc` applied first (its real outputs feed `foundation`'s inputs via a Terragrunt `dependency` block — see `terragrunt/README.md`'s "Dependencies between units"). `foundation`'s `plan` alone is safe with `--backend-bootstrap` (it just needs the bucket to exist to read/write a plan's worth of state), and confirms the `dependency` wiring works:

```sh
cd ../foundation/
terragrunt init --backend-bootstrap --non-interactive
terragrunt plan
```

This has been run against this exact Floci stack and confirmed working: `github-oidc` applies cleanly (3 resources), and `foundation`'s plan picks up `github-oidc`'s **real** output ARNs (`arn:aws:iam::111111111111:role/github-actions-plan`/`...-apply`, not `mock_outputs`' placeholder values) — proof the `dependency` block resolves correctly once the dependency has actually been applied, not just that the mock fallback works.

**`terragrunt apply` on `foundation` is a different story — do not run it with `--backend-bootstrap` expecting it to just work.** `foundation` creates the very S3 bucket `--backend-bootstrap` creates for its backend — the two collide (`BucketAlreadyExists`) the moment `apply` tries to create `aws_s3_bucket.state`, confirmed by hitting this directly in Step 10 of the ROADMAP. See `terraform/modules/account-foundation/README.md`'s "The first-ever apply in a real account" section for the actual procedure (temporary local backend → remove override → `init -migrate-state -force-copy`) before ever running `foundation`'s first real `apply`, here or against real AWS.

## A real bug this stack caught

The first real `terraform init` ever run against this project (previously only `terragrunt render` had been exercised, which doesn't download the module source) surfaced a genuine bug already merged to `main`: both `github-oidc/terragrunt.hcl` and `foundation/terragrunt.hcl`'s `terraform { source = ... }` used `../../../../../terraform/modules/<name>` (5 `../`) when the actual directory depth (`live/<account>/<region>/<env>/<unit>/` → 5 segments, inside `terragrunt/` itself) requires 6. Fixed in both `live/nonprod/...` and `live/floci-local/...` copies. This is exactly the kind of gap a local, real-`init` test stack is for — `terragrunt render` alone never would have caught it.

## A real design gap this stack caught: the state-bucket bootstrap problem

Running a real `terragrunt init` on `github-oidc` against Floci surfaced a second, more fundamental issue: a circular bootstrap dependency.

- `root.hcl` generates an S3 `remote_state` block for **every** unit, pointing at `<account_name>-terraform-state` — a bucket created by the `account-foundation` module.
- `github-oidc` must be applied **before** `account-foundation` (its outputs feed `account-foundation`'s IAM trust-principal inputs via a Terragrunt `dependency` block).
- So `github-oidc`'s own state would need to live in a bucket that doesn't exist yet, created by a module that can't run until after `github-oidc` already has.

This isn't specific to Floci or to this project's design — it's a well-known Terraform/Terragrunt problem ("the thing that manages remote state doesn't have remote state to start with"). Researched against HashiCorp's own documented pattern and a closely analogous real reference architecture ([bezilla/terragrunt-reference-architecture](https://github.com/bezilla/terragrunt-reference-architecture), which hit the identical problem), the resolution adopted here: **`github-oidc` keeps local Terraform state permanently**, deliberately overriding `root.hcl`'s generated S3 backend with its own `remote_state { backend = "local" }` block — see the comment in `terragrunt/live/nonprod/us-east-1/dev/github-oidc/terragrunt.hcl` for the full reasoning. Terragrunt's own `--backend-bootstrap` flag was considered and rejected for this: it solves "the bucket doesn't exist," not "this unit must apply before the bucket-creating unit."

Consequences, by design:
- `github-oidc` is applied by hand only, by a human with real credentials — never by CI, never via `terragrunt run-all` (there's no shared bucket for `run-all` to discover its state in).
- Its `.tfstate` is committed to git (see the root `.gitignore`'s explicit carve-out) rather than kept purely local-to-disk — it contains nothing sensitive (IAM role ARNs, an OIDC provider ID), and committing it means the record of what's actually applied doesn't depend on one person's machine.

## A real bug the "permanent local state" fix itself had

The first version of `github-oidc`'s `remote_state { backend = "local" }` block used a bare relative `config.path = "terraform.tfstate"`. Running a real `apply` against Floci, then deleting `.terragrunt-cache` to simulate a clean checkout, lost that state file entirely — it had actually been written to `.terragrunt-cache/<random-hash>/<random-hash>/.terraform/terraform.tfstate`, not the unit's own directory. Terragrunt v1.x always runs Terraform from inside that ephemeral, randomly-named cache directory (confirmed: there's no opt-out in 1.1.6, unlike pre-v1 behavior — see [gruntwork-io/terragrunt#6199](https://github.com/gruntwork-io/terragrunt/issues/6199)), so a relative path in `remote_state.config` resolves inside it, not next to `terragrunt.hcl`. Fixed by anchoring the path with Terragrunt's `get_terragrunt_dir()` built-in function (`${get_terragrunt_dir()}/terraform.tfstate`), which returns the directory the real `terragrunt.hcl` file lives in regardless of where Terraform actually executes. Re-verified: applied, deleted `.terragrunt-cache`, re-planned — `No changes. Your infrastructure matches the configuration.` The state survived.

## A real bug this stack caught: `.tfvars` leaking into `.terragrunt-cache`

Any `terraform.tfvars` left in `terraform/modules/<name>/` for standalone module testing (per that module's README — gitignored, never committed) gets silently copied along with the rest of the module source into `.terragrunt-cache` every time Terragrunt downloads that module as a unit's `source`. Terraform loads any `terraform.tfvars` it finds in its working directory automatically, with no flag required — so a value meant only for isolated `terraform plan -var-file=terraform.tfvars.example` testing (e.g. a placeholder `kms_key_administrator_arns` ARN) silently leaked into a real `terragrunt plan` on `foundation` run from this stack, producing a plan that didn't match what `env.hcl` actually specified. There's no Terragrunt-level fix for this in v1.1.6 (no per-unit `exclude_from_copy` for arbitrary files) — the only mitigation is discipline: don't leave a real `terraform.tfvars` sitting in a module directory once you're done testing it standalone, especially if you're about to run `terragrunt plan`/`apply` on a unit that uses that same module as its `source`.

## A real bug this stack caught: `foundation`'s self-reference on its first-ever apply

`foundation` creates the S3 bucket meant to hold every unit's Terraform state in the account — including its own. Using `terragrunt init --backend-bootstrap` to work around the "bucket doesn't exist yet" problem (the same flag that's genuinely fine for a `plan`, see above) breaks the moment a real `apply` runs: `--backend-bootstrap` creates a bare bucket for the backend, then `foundation`'s own `aws_s3_bucket.state` resource tries to create that same bucket again and fails with `BucketAlreadyExists` — confirmed by hitting it directly, during Phase 2's provider-upgrade validation (ROADMAP.md Step 10). Resolved with the standard "local state first, migrate after" pattern — the full procedure (and why it's a one-time, by-hand thing, never something CI does) is in `terraform/modules/account-foundation/README.md`'s "The first-ever apply in a real account" section.

## A real bug found in Floci itself: ECR `IMMUTABLE` rejects a repository's very first push

Validating `ecr-repositories` (ROADMAP.md Step 12) surfaced a bug in Floci's own ECR emulation, not in this project's Terraform: a repository created with `image_tag_mutability = "IMMUTABLE"` rejects the first-ever `docker push` of any tag — including one that's never existed in that repository before — with `"tag ... already exists and cannot be overwritten"`. Reproduced three separate times (a fresh tag on a freshly-applied repo, a different tag on the same repo, a first push to a second, completely empty repository) to rule out digest caching or a stale artifact. Switching the same repository to `MUTABLE` and re-pushing the identical image succeeded immediately, no error.

This is a known limitation of this local stack, not a reason to change `ecr-repositories`' own default (`IMMUTABLE` stays, since it's the generally-recommended setting and real AWS ECR doesn't have this bug) — when validating `docker push` against this stack specifically, use `MUTABLE` to actually exercise the push path; `IMMUTABLE` itself needs real AWS to validate.

## Ports

Only `4566` needs an explicit `ports:` mapping (see `docker-compose.yml`). EKS's k3s API servers (host port range `6500-6599`) and every other service-specific range are bound directly on the host by Docker itself when Floci starts those containers — not proxied through the Floci container, so no additional compose configuration is needed for them. See [Floci's ports reference](https://floci.io/floci/configuration/ports/) if a service beyond what this project uses needs a mapped range (ElastiCache, RDS, Neptune, MWAA, Amazon MQ all proxy through Floci's own container and do need one).

## Scope of this investigation phase

This stack validates the **control-plane** side of what Terraform/Terragrunt provision: that `terraform apply` succeeds, that resources are created with the right shape, that the `dependency` + `mock_outputs` wiring between units resolves correctly end to end. It does **not** validate real compute behavior — Floci's EKS node groups, Karpenter, and Auto Mode are metadata-only (see [Floci's EKS service docs](https://floci.io/floci/services/eks/)); nothing about real autoscaling, real pod scheduling under load, or real AWS networking edge cases is exercised here. Treat a clean `terragrunt apply` against this stack as "the Terraform is well-formed and internally consistent," not as "this is production-ready."
