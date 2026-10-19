# Trailmark: three-tier AWS infrastructure with Terraform

A three-tier application stack on AWS, written as reusable Terraform modules, deployed as separate `dev` and `prod` environments, with infrastructure changes reviewed and applied through GitHub Actions and no stored AWS credentials.

Trailmark is the scenario: a startup that publishes hiking trail guides and needs a trail-search backend whose database is never reachable from the internet.

## What's in the repo

| Path | What it is |
|---|---|
| [`modules/`](modules) | The three tiers as modules: `network` (VPC, subnets, gateways), `app-tier` (ALB, Auto Scaling Group) and `db-tier` (RDS Postgres, Secrets Manager) |
| [`envs/`](envs) | The root config that wires the modules together; `dev` and `prod` are Terraform workspaces. See [envs/README.md](envs/README.md) |
| [`pipeline/`](pipeline) | GitHub Actions CI/CD: `bootstrap/` creates the OIDC provider and IAM roles, `stack/` is what the pipeline applies. See [pipeline/README.md](pipeline/README.md) |
| [`state-backend/`](state-backend) | The S3 bucket that holds Terraform state for everything above |
| [`.github/workflows/`](.github/workflows) | `plan.yml` runs on pull requests, `apply.yml` runs on merge to `main` |
| [`docs/decisions.md`](docs/decisions.md) | Why it is built this way, and what each choice costs |

## Getting started

You need Terraform `~> 1.15.8`, AWS credentials, and the region set to `us-east-1`. The state bucket has to exist first (`state-backend/`), then see [envs/README.md](envs/README.md) to stand up an environment.

The `dev` and `prod` stacks include a NAT gateway and an RDS instance, which bill by the hour. Destroy an environment when you are done with it; the teardown steps are in [envs/README.md](envs/README.md).

## History

This project grew in five stages, preserved as the tags `chapter-1` to `chapter-5`. Check out a tag to see the repo as it was at that point.
