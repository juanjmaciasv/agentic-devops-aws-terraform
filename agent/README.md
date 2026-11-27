# Autonomous DevOps agent

`agent/run.sh` launches Claude Code headlessly with the `devops-orchestrator` agent
(`.claude/agents/devops-orchestrator.md`), which executes `agent/instructions.md`
end to end and delegates to three specialists:

| Agent | Role |
|---|---|
| `devops-orchestrator` | Phases 1-8 of the challenge, idempotent: inspects state, resumes at the first incomplete phase, verifies exit criteria |
| `ci-doctor` | Reads failed GitHub Actions logs, fixes the root cause, validates locally, pushes, re-watches |
| `terraform-auditor` | Checklist audit of ECS/ALB/IAM/SG defects that pass `terraform validate` |
| `deploy-verifier` | Stable service, healthy targets, 20/20 HTTP 200 via the ALB; diagnoses from ECS events, task stop reasons, logs |

```bash
aws login --profile personal       # short-lived creds, exported to the run only
agent/run.sh plan                  # safe: no apply / merge, writes "Pending approvals"
agent/run.sh auto                  # fully autonomous, incl. merges and terraform apply
```

**Guardrails**: tool allowlist and denylist per mode (no `terraform destroy`, no force
push, no direct pushes to devel/stage/main, no IAM keys); max 3 attempts per phase;
progress in `agent/RUN_REPORT.md`; full transcripts in `.chat-history/`.

**In CI**: `.github/workflows/self-heal.yaml` runs `ci-doctor` automatically when the CI
Pipeline fails on a feature/ or bugfix/ branch (needs the `ANTHROPIC_API_KEY` secret).
Note: commits pushed with `GITHUB_TOKEN` do not re-trigger CI; use a GitHub App token
for a fully closed loop.
