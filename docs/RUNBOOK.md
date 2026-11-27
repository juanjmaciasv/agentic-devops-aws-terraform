# Runbook

Account `589836822070`, region `us-east-1`. Repo `juanjmaciasv/agentic-devops-aws-terraform`.

## Prerequisites

| Tool | Version | Notes |
|---|---|---|
| Node / npm | 15.5.1 / 7.x | From `.nvmrc`; `engine-strict` rejects anything else. `agent/run.sh` downloads it automatically |
| Terraform | >= 1.10 (CI: 1.16.1) | S3 native locking needs 1.10+ |
| AWS CLI v2 | | `aws login --profile personal` (short-lived) |
| gh | | `gh auth login` **with `-s workflow`** or pushes touching `.github/workflows` are rejected |

`aws login` sessions are not readable by the Terraform provider. Export them into the shell only:

```bash
eval "$(aws configure export-credentials --profile personal --format env)"
```

## 1. One-time bootstrap (admin, local)

```bash
cd terraform/bootstrap
terraform init && terraform plan -out=bootstrap.tfplan && terraform apply bootstrap.tfplan
terraform output   # state_bucket, ecr_repository_url, deploy_role_arn
```

Then configure GitHub (already done for this repo):

```bash
gh variable set AWS_DEPLOY_ROLE_ARN --body "$(terraform output -raw deploy_role_arn)"
gh variable set ECR_REPOSITORY_URL  --body "$(terraform output -raw ecr_repository_url)"
gh variable set AWS_REGION          --body us-east-1
# Environments devel and stage, each with a deployment-branch policy = its own branch
```

Bootstrap state is local and gitignored. Back up `terraform/bootstrap/terraform.tfstate`.

## 2. Normal change flow

1. `git switch devel && git pull && git switch -c feature/<name>` (or `bugfix/<name>`)
2. Push and open a PR into `devel`. Required checks: `branch-policy`, `build` (CI), plus CD `plan`.
3. Merge. CD on `devel` then: build image `:<sha>`, push to ECR, run `terraform apply` with the devel env, then `scripts/verify-deploy.sh`.
4. Promote: PR `devel` into `stage` (the `branch-policy` job rejects any other source). Same pipeline, stage env.

Manual redeploy: Actions, **CD Pipeline**, *Run workflow*, pick the environment.

## 3. Verify an environment

```bash
cd terraform
terraform init -reconfigure -backend-config=envs/devel.backend.hcl
../scripts/verify-deploy.sh \
  "$(terraform output -raw cluster_name)" "$(terraform output -raw service_name)" \
  "$(terraform output -raw target_group_arn)" "$(terraform output -raw alb_dns_name)" 20
terraform output -raw app_url
```

Pass = running == desired, all targets `healthy`, 20/20 `200` on `/health` and `/`.

## 4. Troubleshooting

| Symptom | Look at | Usual cause |
|---|---|---|
| CI `ENOTSUP` | install log | Node not from `.nvmrc` |
| CI lint `couldn't find the plugin` | lint log | eslint-plugin/config-prettier missing or wrong major |
| CD `Not authorized to perform sts:AssumeRoleWithWebIdentity` | `gh api repos/<repo>/actions/oidc/customization/sub` | OIDC `sub` mismatch: environment vs ref, or immutable subject prefix |
| Push rejected `without workflow scope` | `gh auth status` | `gh auth refresh -s workflow` |
| Tasks stop, `CannotPullContainerError` | `aws ecs describe-tasks … stoppedReason` | Execution role or no public IP (no NAT) |
| Tasks exit immediately | CloudWatch `/ecs/rdicidr-<env>` | nginx config error |
| Targets `unhealthy` (`Target.ResponseCodeMismatch`) | `aws elbv2 describe-target-health` | Health path doesn't match nginx |
| Targets `Target.Timeout` | security groups | `ecs-sg` doesn't allow `alb-sg` on the app port |
| Service events `unable to place` | `aws ecs describe-services … events` | Subnets in an unsupported AZ |
| Deploy rolled back | service events | Circuit breaker: new tasks failed health; fix and redeploy |

Agent shortcut: `claude` then "use deploy-verifier on devel".

## 5. Tear down (stop charges, about $0.05/h per env)

```bash
eval "$(aws configure export-credentials --profile personal --format env)"
cd terraform
for env in devel stage; do
  terraform init -reconfigure -backend-config=envs/$env.backend.hcl
  terraform destroy -var-file=envs/$env.tfvars -var container_image=unused
done
# Optional, last: removes state bucket, ECR (force_delete) and the OIDC role
cd bootstrap && terraform destroy
```

The agent is deliberately **denied** `terraform destroy`; teardown is a human action.
