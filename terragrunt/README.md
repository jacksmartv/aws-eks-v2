# terragrunt/

The environment-composition layer of this project (ADR-002). Terraform owns what infrastructure looks like; this tree owns which account/region/environment gets which infrastructure, and with what values.

## Hierarchy

```
terragrunt/
├── root.hcl                                # root: generates the S3 backend + AWS provider blocks for every unit
├── _accounts/
│   └── <account>/account.hcl               # one file per AWS account — account_id, is_payer_account
└── live/
    └── <account>/<region>/<env>/
        ├── env.hcl                         # the ONE file that defines this environment's values
        ├── foundation/terragrunt.hcl       # invokes terraform/modules/account-foundation
        ├── network/terragrunt.hcl          # invokes terraform/modules/network (not yet built)
        ├── ecr/terragrunt.hcl              # invokes terraform/modules/ecr-repositories (not yet built)
        ├── eks-cluster/terragrunt.hcl      # invokes terraform/modules/eks-cluster (not yet built)
        └── gitops-bootstrap/terragrunt.hcl # invokes terraform/modules/gitops-bootstrap (not yet built)
```

Four levels: account → region → environment → unit. Each level is a directory; nothing about the hierarchy is encoded as a conditional inside an `.hcl` file — see ADR-002 for why that distinction matters.

## The two data files, and why there are exactly two

**`account.hcl`** holds only what's true about the AWS account itself, independent of any environment inside it: the account ID, and whether it's the AWS Organizations payer account (used to scope cost-allocation-tag activation — see `MASTERPLAN.md §6`). An account can host multiple environments (e.g. both `dev` and `staging` in the same `nonprod` account), so this data is deliberately separate from environment-level data.

**`env.hcl`** holds everything else: region, cost-allocation tags (`CostCenter`/`Team`/`Owner`), and every input value every unit in that environment needs (state bucket settings, KMS settings, IAM role trust principals, etc. — currently just `account-foundation`'s inputs; more will accumulate here as `network`, `ecr`, `eks-cluster`, and `gitops-bootstrap` are built). This is the file described elsewhere in this project as "the one file you change" for a given environment — every unit reads it via `read_terragrunt_config(find_in_parent_folders("env.hcl"))`, so a value changed once is picked up everywhere in that environment without being duplicated per-unit.

Neither file contains provider logic or resource-shaping conditionals — they're pure data, consumed by the root `root.hcl` and by each unit's own `terragrunt.hcl`.

## A quirk worth knowing: `account.hcl` can't be found by `find_in_parent_folders()`

`env.hcl` sits in a real parent directory of every unit (`live/<account>/<region>/<env>/`), so `find_in_parent_folders("env.hcl")` finds it by walking upward — that's the normal Terragrunt pattern and it works here without anything special.

`_accounts/<account>/account.hcl` does **not** work the same way — it's a *sibling* branch of the `live/` tree, not an ancestor of any unit, so `find_in_parent_folders("account.hcl")` fails no matter how far it walks up. Both the root `root.hcl` and each unit's own `terragrunt.hcl` resolve it explicitly instead, by combining `env.hcl`'s own directory with a fixed number of `../` segments up to the `terragrunt/` root, plus the `account_name` that `env.hcl` itself declares:

```hcl
account_vars = read_terragrunt_config(
  "${dirname(find_in_parent_folders("env.hcl"))}/../../../../_accounts/${local.env_vars.locals.account_name}/account.hcl"
)
```

If the hierarchy depth ever changes (e.g. a level is added or removed between `live/` and a unit), this relative path needs updating everywhere it appears — currently that's the root `root.hcl` and every unit's `terragrunt.hcl` under `live/`.

## Running a unit

```sh
cd terragrunt/live/<account>/<region>/<env>/<unit>/

terragrunt render --format json   # resolve everything (backend, provider, inputs) with zero AWS credentials needed
terragrunt plan                   # requires valid AWS credentials for the target account
terragrunt apply
terragrunt destroy
```

`terragrunt render` is the cheapest way to verify a unit is wired correctly — it prints the fully-resolved backend config, generated provider block, and module inputs without touching AWS at all. Run it after changing any `.hcl` file in this tree, before running `plan`.

See the root [`README.md`](../README.md#running-this-project-terragrunt) for the full walkthrough, including the KMS `PendingDeletion` note relevant to `foundation`.

## A guard worth understanding: `allowed_account_ids`

The generated `provider.tf` only sets `allowed_account_ids` when `account.hcl`'s `account_id` is non-empty. An `account_id = ""` placeholder (the state every new account starts in, before a real AWS account exists) deliberately produces **no** account restriction at all — not a restriction to an empty string, which would hard-block every `plan`/`apply`/`destroy` against any account (the AWS provider does a strict equality check; `[""]` never matches a real account ID). This means an environment with a blank `account_id` has zero protection against accidentally applying against the wrong AWS account — filling in the real `account_id` is the first thing to do before running anything beyond `terragrunt render` against a new account. See `_accounts/<account>/account.hcl`'s own comments and `root.hcl`'s `allowed_account_ids_block` local for the mechanics.

## Formatting

```sh
terragrunt hcl format                    # formats every .hcl file in this tree
terragrunt hcl format --check --diff     # verifies formatting without changing anything (used in CI)
```
