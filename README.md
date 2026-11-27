# Agentic DevOps: CI repair + Terraform ECS Fargate on AWS

A partly broken React app (rdiCidr) with a seeded-defect CI pipeline and Terraform stack,
repaired and deployed by AI agents (Claude Code), plus an **autonomous agent** that can
run the whole challenge end to end on its own.

| Doc | What it covers |
|---|---|
| [docs/AGENT.md](docs/AGENT.md) | The autonomous agent: architecture, phases, guardrails, how to run it |
| [docs/RUNBOOK.md](docs/RUNBOOK.md) | Operating the platform: deploy, promote, verify, troubleshoot, tear down |
| [docs/DEFECTS.md](docs/DEFECTS.md) | Every seeded defect: evidence, root cause, fix |
| [docs/LESSONS_LEARNED.md](docs/LESSONS_LEARNED.md) | What went wrong along the way and what we'd do differently |

## Architecture

```
 feature/* | bugfix/*  --PR-->  devel  --PR-->  stage        (rulesets: no direct push, checks required)
        │                        │               │
   CI Pipeline              CD Pipeline      CD Pipeline     (GitHub Actions, OIDC -> AWS, no static keys)
   branch-policy            build image -> ECR (tag = git SHA, immutable)
   install                  terraform apply (env state in S3, native locking)
   lint + test              verify: service stable, targets healthy, 20/20 HTTP 200
   build
                                  │
          Internet ──80──> ALB (alb-sg) ──80──> ECS Fargate tasks x2 (ecs-sg: ALB only)
                                                nginx serving the CRA build, /health
```

- **Workflows**: `.github/workflows/ci.yaml` (CI), `cd.yaml` (PR plan, deploy on merge),
  `self-heal.yaml` (AI agent fixes failing CI on work branches)
- **Terraform**: `terraform/bootstrap/` (state bucket, ECR, GitHub OIDC deploy role; applied once)
  and `terraform/` (app stack; per-env `envs/<env>.tfvars` + `envs/<env>.backend.hcl`)
- **Agents**: `.claude/agents/` (orchestrator + ci-doctor, terraform-auditor, deploy-verifier),
  run by `agent/run.sh [plan|auto]`

## Quick start

```bash
# CI locally (Node from .nvmrc: 15.5.1)
npm ci && npm run lint && npm run prettier && CI=true npm test && npm run build

# Whole challenge, autonomously
aws login --profile personal
agent/run.sh plan     # safe dry run
agent/run.sh auto     # merges PRs + terraform apply
```

---

# Original app README

# rdiCidr

Ok, let's get this out of the way. Why did I choose that name? I chose the name because palindromes are fun. The app's name stands for RDerik's Interactive  CIDR (RDICIDR). I had to add the Interactive to make the name work. I hope you like it.

RDICIDR is a react-app, but if you want to focus on the subnetting code, check the file:

```
src/lib/ipv4.js
```

You should find there how each property was calculated.

This application is not a final product. I just built it because I wanted to refresh my subnetting knowledge. Enjoy!

# Live version

You can find a live version at the following url:

[https://rdicidr.rderik.com](https://rdicidr.rderik.com)

If you find this tool useful, you might enjoy reading my blog: [https://rderik.com](https://rderik.com)
