# Design decisions

The reasoning behind the choices in this repo, and what each one costs. The original step-by-step guides are kept in git history: `git show chapter-N:CHAPTER-N-GUIDE.md`, or browse the `chapter-1` to `chapter-5` tags.

## Three tiers, isolated by security-group references

The network is a VPC across two AZs with three subnet tiers: public (ALB), private (app, in an Auto Scaling Group) and isolated (RDS Postgres). Each tier accepts traffic only from the security group of the tier above it, by reference rather than by CIDR range, so the database is unreachable from the internet and from anything except the app tier. The database master password is generated and stored in Secrets Manager by RDS itself (`manage_master_user_password`), so it is never in `.tf` files, variables or Terraform state.

The three tiers are separate modules (`modules/network`, `modules/app-tier`, `modules/db-tier`) composed once per environment in `envs/`.

## Dev and prod: Terraform workspaces, one root config

`envs/` is a single root config; `dev` and `prod` are workspaces, with sizing in `dev.tfvars` and `prod.tfvars`. Dev uses one NAT gateway and a single app instance; prod uses a NAT gateway per AZ, two to four instances.

**What it costs.** Two independent selectors choose the environment: `terraform workspace select` picks the state, and `-var-file` picks the names and sizing. Nothing ties them together, so `workspace select prod` with `-var-file=dev.tfvars` plans cleanly and writes dev-named resources into prod's state. This happened once during development. A folder per environment would make `cd` the only selector, at the price of near-duplicate code. Collapsing to one selector (derive the prefix from `terraform.workspace`, key sizing by workspace) is a known follow-up.

## State: S3 backend with native locking

State lives in `s3://trailmark-state-backend` with `use_lockfile = true`, so no DynamoDB lock table is needed. The bucket is created by `state-backend/`, which is applied by hand because the backend cannot create itself. State keys are the identity of a config, not of an environment: the workspace prefix supplies the environment.

## CI/CD: GitHub Actions with OIDC, no stored credentials

A pull request posts `terraform plan` as a comment; a merge to `main` runs `terraform apply`. GitHub authenticates to AWS by assuming a role through its OIDC provider, so no AWS access keys exist in GitHub.

- **Two roles.** The PR job runs unreviewed code, so it gets a role that can only plan. The apply role is trusted only from `refs/heads/main`.
- **The trust policy is the security story.** Each role's `sub` condition is an exact match on this repository (owner and repository IDs, since immutable subject claims are enabled), never a wildcard. A missing or wildcard `sub` would let any repository on GitHub assume the role.
- **Bootstrap by hand.** The OIDC provider and the two roles are applied locally from `pipeline/bootstrap/`, because a pipeline cannot create its own credentials. CI never touches `bootstrap/`; the apply role's state permission is scoped to the `stack` state keys only.
- **Plan output goes in a PR comment, never an artifact.** A plan file contains every attribute in the clear and artifacts outlive the run. The stack has no secrets in it, which is what makes posting safe.

## The pipeline deploys a small stack, not the three-tier one

`pipeline/stack` is a single versioned S3 bucket. Automating the three-tier stack was rejected on purpose: getting a pipeline working takes many pushes, and each push against a NAT gateway and RDS is a ten-minute apply and real money; "apply on merge" would bill the two most expensive resources on every merge; and that stack generates database passwords, which is exactly what must not be printed into PR comments. The pipeline mechanics are identical whatever sits underneath.

## Known gaps

- The app tier runs a small HTTP stub that answers `/health`; there is no application behind it yet.
- The ALB listens on HTTP (port 80) only.
- The apply job has no manual approval gate; a GitHub Environment with required reviewers would add one.
- The environment-selector problem described above is documented, not fixed.
