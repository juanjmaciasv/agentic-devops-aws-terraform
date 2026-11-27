#!/usr/bin/env bash
# Runs the devops-orchestrator agent headlessly against agent/instructions.md.
#
#   agent/run.sh [plan|auto]
#     plan (default): investigates, fixes code, validates, opens PRs; stops before
#                     any `terraform apply` / `gh pr merge` (human approves).
#     auto:           fully autonomous end to end, including merges and AWS apply.
#
# Env: AWS_PROFILE (default: personal), REPO (default: current gh repo),
#      MAX_TURNS (default: 200)
# Every run's full transcript (stream-json) is saved to .chat-history/ for review.
set -euo pipefail
cd "$(dirname "$0")/.."

MODE=${1:-plan}
case "$MODE" in plan|auto) ;; *) echo "usage: $0 [plan|auto]"; exit 2 ;; esac
export AGENT_MODE=$MODE
export AWS_PROFILE=${AWS_PROFILE:-personal}
export REPO=${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}
export AWS_REGION=${AWS_REGION:-us-east-1}

# Preflight: fail fast with a clear message instead of letting the agent flail
for t in claude gh git terraform aws node npm curl; do
  command -v "$t" >/dev/null || { echo "missing tool: $t"; exit 1; }
done
# Pin Node to .nvmrc (package.json engines + engine-strict reject other versions)
NODE_V=$(cat .nvmrc)
if [ "$(node -v 2>/dev/null)" != "v$NODE_V" ]; then
  NODE_DIR=${XDG_CACHE_HOME:-$HOME/.cache}/rdicidr-node/node-v$NODE_V-linux-x64
  [ -x "$NODE_DIR/bin/node" ] || { mkdir -p "${NODE_DIR%/*}"; \
    curl -fsSL "https://nodejs.org/dist/v$NODE_V/node-v$NODE_V-linux-x64.tar.xz" | tar xJ -C "${NODE_DIR%/*}"; }
  export PATH="$NODE_DIR/bin:$PATH"
fi
echo "node $(node -v) / npm $(npm -v)"
gh auth status >/dev/null 2>&1 || { echo "gh not authenticated: gh auth login -s workflow"; exit 1; }
gh auth status 2>&1 | grep -q workflow || echo "warning: gh token may lack 'workflow' scope"
# Short-lived creds exported to this process only (works with `aws login` sessions,
# which the Terraform AWS provider cannot read directly). Nothing written to disk.
eval "$(aws configure export-credentials --profile "$AWS_PROFILE" --format env)" \
  || { echo "AWS session expired: aws login --profile $AWS_PROFILE"; exit 1; }
aws sts get-caller-identity --query Arn --output text

# Bash arrays: each rule stays ONE argument (rules contain spaces and globs)
ALLOWED=(Read Edit Write Grep Glob Agent
  'Bash(git:*)' 'Bash(gh:*)' 'Bash(npm:*)' 'Bash(npx:*)' 'Bash(node:*)'
  'Bash(terraform fmt:*)' 'Bash(terraform init:*)' 'Bash(terraform validate:*)'
  'Bash(terraform plan:*)' 'Bash(terraform output:*)' 'Bash(terraform -chdir=*)'
  'Bash(aws sts:*)' 'Bash(aws ecs:*)' 'Bash(aws elbv2:*)' 'Bash(aws logs:*)'
  'Bash(aws ecr describe-*:*)' 'Bash(curl:*)' 'Bash(scripts/verify-deploy.sh:*)'
  'Bash(cat:*)' 'Bash(ls:*)' 'Bash(grep:*)' 'Bash(sed:*)' 'Bash(jq:*)'
  'Bash(cd:*)' 'Bash(echo:*)' 'Bash(mkdir:*)' 'Bash(sleep:*)' 'Bash(test:*)'
  'Bash(head:*)' 'Bash(tail:*)' 'Bash(aws ec2 describe-*:*)' 'Bash(aws iam get-*:*)')
DISALLOWED=('Bash(terraform destroy:*)' 'Bash(git push --force:*)'
  'Bash(gh repo delete:*)' 'Bash(aws iam create-access-key:*)')
if [ "$MODE" = plan ]; then
  DISALLOWED+=('Bash(terraform apply:*)' 'Bash(gh pr merge:*)')
else
  ALLOWED+=('Bash(terraform apply:*)' 'Bash(gh pr merge:*)')
fi

mkdir -p .chat-history
LOG=.chat-history/agent-run-$(date -u +%Y%m%dT%H%M%SZ)-$MODE.jsonl
echo "mode=$MODE repo=$REPO log=$LOG"

claude -p "Use the devops-orchestrator agent. Execute agent/instructions.md end to end for repo $REPO in $MODE mode. Resume from the first incomplete phase. Append progress to agent/RUN_REPORT.md and finish with the public ALB URL and a defect/fix summary." \
  --permission-mode dontAsk \
  --allowedTools "${ALLOWED[@]}" \
  --disallowedTools "${DISALLOWED[@]}" \
  --max-turns "${MAX_TURNS:-200}" \
  --output-format stream-json --verbose < /dev/null \
  | tee "$LOG" \
  | jq -rj 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text + "\n"'

echo "transcript: $LOG"
