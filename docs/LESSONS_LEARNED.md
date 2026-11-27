# Lessons learned

## About the defects

**L1. "Validate passes" means almost nothing.** Every Terraform defect was syntactically
valid. The real bugs sat at the seams *between* files: task definition vs target group
(ports), target group vs nginx.conf (health path), Dockerfile vs nginx's include layout,
IAM policy vs what ECR actually requires. Review cross-references, not files.

**L2. Fix the trigger first, then let the pipeline tell you the rest.** Fixing only the `on:`
block first turned the pipeline into the diagnostic tool and produced the required
"failed run" naturally. Reading the YAML also caught defects (cache key, `needs:`) that
would only have shown up after earlier failures were fixed, which saves iterations.

**L3. Version pins form a chain.** Prettier 3 needs eslint-plugin-prettier 5, which needs
ESLint 8, but react-scripts 4 ships ESLint 7. Upgrading the leaf breaks the root; the fix is
to move the leaf down. Regenerate lockfiles with the *same* Node/npm as CI (npm 7 / Node 15).

**L4. Secure defaults are also correctness fixes.** Splitting the ALB and task security
groups, using the managed execution policy, and adding a circuit breaker each removed a
whole class of "intermittent" failures.

## About the platform

**L5. OIDC subjects are not what you think.** Two separate surprises:
(a) a job with `environment:` gets `sub = repo:…:environment:<name>`, not the branch ref;
(b) this repo uses GitHub's *immutable* subject format `repo:owner@<id>/repo@<id>:…`.
Check with `gh api repos/<repo>/actions/oidc/customization/sub` **before** writing the
trust policy. The agent diagnosed (b) from the CD log on its own.

**L6. Headless sub-agents must run in the foreground.** The orchestrator launched the
terraform-auditor in the background and returned early. The top-level session had to resume
it. Rule now in the orchestrator: delegate synchronously, never in parallel on the same files.

**L7. Shell quoting is part of the security boundary.** The first `run.sh` passed permission
rules as one unquoted string; bash split `Bash(terraform -chdir=*)` at the space and the CLI
choked. Unquoted globs could also have expanded against files. Use arrays: `"${ALLOWED[@]}"`.

**L8. Local environment differs from CI, so make it match explicitly.** Missing Docker
permissions, the wrong Node, an `aws login` session Terraform can't read, and a `gh` token
without `workflow` scope each cost a few minutes. `agent/run.sh` now preflights all of them
and pins Node from `.nvmrc`; image builds happen in Actions.

## About guiding AI

**L9. Human-in-the-loop for irreversible steps is a feature.** Merges and `terraform apply`
were gated (by the tool's permission classifier and by `plan` mode). That forced explicit
approval points, which is right for prod and cheap to switch off (`auto`) when intended.

**L10. Make the agent resumable, not just autonomous.** Inspect-then-act phases let a
half-done, human-guided run hand off cleanly to the agent, and let a failed run restart
without redoing or duplicating work.

**L11. Narrate root causes, not symptoms.** For every fix: quote the error line, name the
cause, explain why the change fixes it. It's the same format the agents write to RUN_REPORT.md.

## If we did it again

- Check the OIDC subject format and `gh` scopes in the first minute.
- Put the deploy role's PR-plan permissions in a separate read-only role from the start.
- Have `run.sh` stream sub-agent tool calls to the terminal, not only final text.
- Time-box: CI in about 15 minutes, Terraform review in about 10, deploy in about 15, packaging in about 5.
