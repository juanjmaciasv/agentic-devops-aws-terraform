# The autonomous DevOps agent

Goal: given only `agent/instructions.md` (the challenge brief, token redacted), complete
the challenge end to end, with no human edits: repo and branching, CI repair, Terraform
repair, AWS deploy, health verification, packaging.

## Architecture

```
agent/run.sh [plan|auto]                   preflight: tools, gh scopes, AWS creds, Node from .nvmrc
  └─ claude -p (headless, dontAsk)         allowlist/denylist per mode, transcript to .chat-history/
      └─ devops-orchestrator               phases 1-8, inspect -> plan -> act -> verify -> report
          ├─ ci-doctor                     failed run logs -> root cause -> minimal fix -> local validate -> push -> re-watch
          ├─ terraform-auditor             10-point checklist + fmt/validate/plan (never applies)
          └─ deploy-verifier               scripts/verify-deploy.sh + ECS events / stopped tasks / logs / target health
.github/workflows/self-heal.yaml           same ci-doctor, triggered automatically when CI fails on a work branch
```

Definitions live in `.claude/agents/*.md`, so anyone running Claude Code in this repo
gets the same agents interactively (for example "use terraform-auditor").

## Phases and exit criteria

| # | Phase | Done when |
|---|---|---|
| 1 | Repo and branching | main/devel/stage exist, default devel, ruleset blocks push/force-push/delete and requires `branch-policy` + `build` |
| 2 | CI | A PR into devel shows a failed run, then a fully green run; merged |
| 3 | Terraform audit | Checklist all PASS, fmt/validate clean, devel plan OK |
| 4 | Bootstrap | State bucket, ECR, OIDC role applied; repo vars + environments set |
| 5 | Deploy devel | Terraform PR merged; CD push run green |
| 6 | Verify | running == desired, all targets healthy, 20/20 HTTP 200; URL recorded |
| 7 | Promote stage | Optional, PR devel into stage |
| 8 | Package | RUN_REPORT.md summary; transcripts present; no secrets/state/node_modules |

**Idempotent**: each phase inspects real state (gh/git/aws/terraform) first and skips if
done, so the agent can resume a half-finished run. That is how this repo was finished: a
human-guided session fixed the defects, then `agent/run.sh auto` audited them, provisioned
AWS, opened and merged PR #2, and diagnosed and fixed the OIDC failure (D1 in DEFECTS.md).

## Guardrails

| Control | How |
|---|---|
| Two modes | `plan`: `terraform apply` and `gh pr merge` are *disallowed*; the agent lists them under "Pending approvals". `auto`: allowed |
| Never destructive | Denied in every mode and in `.claude/settings.json`: `terraform destroy`, force push, direct push to devel/stage/main, `gh repo delete`, `aws iam create-access-key`, reading tfstate / `~/.aws/credentials` |
| No static secrets | AWS via short-lived `export-credentials` in the run's process; CI via GitHub OIDC |
| Bounded | Max 3 attempts per phase; self-heal stops after 3 consecutive bot commits; `--max-turns 200` |
| No cheating | Agents may not skip tests, disable lint, or loosen `engine-strict` to go green |
| Auditable | Full stream-json transcript per run in `.chat-history/`; progress in `agent/RUN_REPORT.md` |

## Running it

```bash
aws login --profile personal
agent/run.sh plan      # dry run
agent/run.sh auto      # end to end
# watch live in a second terminal:
tail -f .chat-history/agent-run-*.jsonl | jq --unbuffered -r 'select(.type=="assistant")
  | .message.content[]? | if .type=="tool_use" then "▶ \(.name): \(.input.command // .input.description // "")"
  elif .type=="text" then "💬 \(.text)" else empty end'
```

Env: `AWS_PROFILE` (default `personal`), `REPO`, `MAX_TURNS`.
Self-heal in CI needs the `ANTHROPIC_API_KEY` repo secret (`gh secret set ANTHROPIC_API_KEY`).

## Why not AWS Bedrock AgentCore?

Considered and rejected for this scope: it isn't free-tier, needs extra runtime, IAM and
model-access setup, and is harder to audit in a review. The agent's work is git, gh,
terraform and aws CLI calls against this repo, which runs best next to the code (locally or
in Actions) with an explicit tool allowlist. AgentCore makes sense once the agent must run as
a long-lived, multi-tenant service.

## Known limitations / next steps

- Commits pushed by `GITHUB_TOKEN` in self-heal don't re-trigger CI; use a GitHub App token to close the loop.
- PR plan jobs assume the full deploy role; split a read-only plan role (terraform-auditor finding).
- AZ list defaults to us-east-1; derive from `aws_availability_zones` for other regions.
- Orchestrator must run sub-agents in the **foreground** (see LESSONS_LEARNED.md, L6).
