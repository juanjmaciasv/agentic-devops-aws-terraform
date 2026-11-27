#!/usr/bin/env bash
# Verifies a deployed environment end to end:
#   1. ECS service reaches a steady state with running == desired
#   2. Every target registered in the ALB target group is healthy
#   3. /health and / through the ALB return 200 on N consecutive requests
# Usage: scripts/verify-deploy.sh <cluster> <service> <target_group_arn> <alb_dns> [checks]
set -euo pipefail

CLUSTER=$1 SERVICE=$2 TG_ARN=$3 ALB_DNS=$4 CHECKS=${5:-20}

echo "==> Waiting for ECS service $SERVICE to be stable"
aws ecs wait services-stable --cluster "$CLUSTER" --services "$SERVICE"
read -r RUNNING DESIRED < <(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" \
  --query 'services[0].[runningCount,desiredCount]' --output text)
echo "    running=$RUNNING desired=$DESIRED"
[ "$RUNNING" -eq "$DESIRED" ] && [ "$DESIRED" -gt 0 ] || { echo "::error::service not at desired count"; exit 1; }

echo "==> Waiting for all ALB targets to be healthy"
for i in $(seq 1 40); do
  STATES=$(aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
    --query 'TargetHealthDescriptions[].TargetHealth.State' --output text)
  echo "    attempt $i: ${STATES:-<none>}"
  if [ -n "$STATES" ] && [ "$(echo "$STATES" | tr '\t' '\n' | grep -vc '^healthy$')" -eq 0 ] \
     && [ "$(echo "$STATES" | wc -w)" -ge "$DESIRED" ]; then break; fi
  [ "$i" -eq 40 ] && { echo "::error::targets never became healthy"; \
    aws elbv2 describe-target-health --target-group-arn "$TG_ARN" --output table; exit 1; }
  sleep 15
done

echo "==> $CHECKS consecutive HTTP checks through the ALB (must all be 200)"
for path in /health /; do
  for i in $(seq 1 "$CHECKS"); do
    CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://$ALB_DNS$path" || true)
    [ "$CODE" = "200" ] || { echo "::error::GET $path returned $CODE on attempt $i"; exit 1; }
  done
  echo "    GET $path -> 200 x$CHECKS"
done

echo "==> OK: http://$ALB_DNS is serving traffic with healthy targets"
