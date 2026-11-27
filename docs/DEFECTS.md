# Seeded defects: evidence, root cause, fix

## Part 1: CI pipeline (`.github/workflows/ci.yaml`), PR #1

The first commit fixed only the trigger, so the remaining defects surfaced in real runs:
failed run [46052614655](https://github.com/juanjmaciasv/agentic-devops-aws-terraform/actions/runs/46052614655),
then a fully green run [46053200684](https://github.com/juanjmaciasv/agentic-devops-aws-terraform/actions/runs/46053200684).

| # | Evidence | Root cause | Fix |
|---|---|---|---|
| C1 | Opening a PR into `devel` ran nothing | `on.pull_request.branches: [main]`, push only on `feature-*` (hyphen, not slash) | PRs into `devel`/`stage`/`main`; pushes on `feature/**`, `bugfix/**` |
| C2 | `npm ERR! code ENOTSUP … wanted node >=15 <16 … current 14.21.3` | `node-version: '14'` hard-coded while `.nvmrc` = 15.5.1 and `.npmrc` sets `engine-strict=true` | `node-version-file: .nvmrc` in every job |
| C3 | (found by review) `build` restored `deps-<hash>`, `install` saved `node-modules-<hash>` | Cache key mismatch, so build would run with no `node_modules` | One key; `fail-on-cache-miss: true` so a miss fails loudly |
| C4 | (found by review) `build: needs: [lint]` | Build could pass with failing tests | `needs: [lint, test]` |
| C5 | `ESLint couldn't find the plugin "eslint-plugin-prettier"` | `plugin:prettier/recommended` configured but plugin/config not installed; Prettier 3 needs eslint-plugin-prettier 5, which needs ESLint 8, but CRA 4 ships ESLint 7 | `prettier@2.8.8`, `eslint-plugin-prettier@4.2.1`, `eslint-config-prettier@8.10.0` (lockfile regenerated with npm 7 / Node 15) |
| C6 | `● displays the API endpoint URL … Expected … undefined` | Test reads `process.env.REACT_APP_API_URL`, never provided | Workflow `env` (overridable repo variable) + committed `.env.test` |
| C7 | `prettier/prettier: Insert {" "}⏎` in `src/App.js:14` | File not formatted | `prettier --write src/App.js` |

Hardening in the same PR: `branch-policy` job (only `feature/*`/`bugfix/*` into devel, only
`devel` into stage, only `stage` into main; rulesets can't express source-branch rules),
`permissions: contents: read`, `concurrency`, actions v3 to v4.

## Part 2: Terraform / runtime (`terraform/`, `Dockerfile`, `nginx.conf`), PR #2

All of these pass `terraform validate`.

| # | Root cause | Failure mode | Fix |
|---|---|---|---|
| T1 | No `portMappings` in the container definition | Service can't attach to the target group | `portMappings = [{ containerPort = var.container_port }]` |
| T2 | Inline execution policy lacked `ecr:GetAuthorizationToken` | `CannotPullContainerError`, tasks never start | AWS-managed `AmazonECSTaskExecutionRolePolicy` |
| T3 | Dockerfile copied a bare `server {}` file over `/etc/nginx/nginx.conf` | nginx exits on boot (`server directive is not allowed here`), crash loop | Copy to `/etc/nginx/conf.d/default.conf` |
| T4 | Health check path `/healthz`; nginx serves `/health` | Targets never healthy, so 502/503 | Default `/health`, exact-match `location = /health` |
| T5 | ALB and tasks shared one SG open to `0.0.0.0/0` | Tasks reachable directly, bypassing the ALB | `alb-sg` (80 from internet) + `ecs-sg` (app port from `alb-sg` only) |
| T6 | `ignore_changes = [desired_count, task_definition]`, no autoscaling | New images never roll out | Removed |
| T7 | No `depends_on` listener, no grace period, no circuit breaker | Creation race; tasks killed during startup; bad deploys never roll back | `depends_on`, 60s grace, circuit breaker with rollback, `wait_for_steady_state` |
| T8 | Names not environment-scoped, no backend, placeholder image default, no ECR | devel/stage collide; unshared state; un-pullable image | `local.name = app-env`, S3 backend per env (`use_lockfile`), required `container_image`, ECR in bootstrap |
| T9 | Subnet lookup took every default-VPC subnet | Can land in AZs without full Fargate/ALB support | Filter `availability-zone` + `default-for-az` |
| T10 | `node:15-alpine` + node-sass, `npm install`, `COPY . .`, EOL `nginx:1.21` | Fragile, non-reproducible build | `node:15.5.1-buster-slim`, `npm ci`, scoped COPY, `.dockerignore`, `nginx:1.27-alpine`, HEALTHCHECK |

## Found during deployment (by the autonomous agent)

| # | Evidence | Root cause | Fix |
|---|---|---|---|
| D1 | CD plan: `Not authorized to perform sts:AssumeRoleWithWebIdentity` | Repo uses GitHub's **immutable OIDC subject** (`repo:owner@id/repo@id:…`); the trust policy only allowed `repo:owner/repo:…` | Trust both prefixes for the same 3 subjects (`environment:devel`, `environment:stage`, `pull_request`) |
| D2 | (designed in) deploy jobs use GitHub environments | OIDC `sub` becomes `environment:<name>`, not `ref:refs/heads/<branch>` | Trust policy keyed on environments, each restricted to its own branch |
