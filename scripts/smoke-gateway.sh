#!/usr/bin/env bash
# Smoke test of the platform right after terraform apply (spec RF-007, RF-008, HU-2 criterion 5).
# Usage: scripts/smoke-gateway.sh <api_endpoint>   e.g. https://abc123.execute-api.us-east-2.amazonaws.com
# Needs AWS credentials (reads the SSM contract). Exit 0 when every check passes.
set -euo pipefail

if [[ $# -ne 1 || "$1" != https://* ]]; then
  echo "usage: $0 https://<api-id>.execute-api.<region>.amazonaws.com" >&2
  exit 2
fi
endpoint="${1%/}"
host="${endpoint#https://}"
failures=0

# 1. An unregistered path returns 404 (the stage can take a few seconds to serve after the first deploy).
code=""
for _ in $(seq 1 10); do
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$endpoint/api/v1/__humo__" || true)"
  [[ "$code" == "404" ]] && break
  sleep 6
done
if [[ "$code" == "404" ]]; then
  echo "ok   unregistered route returns 404"
else
  echo "FAIL unregistered route returned $code, expected 404"
  failures=$((failures + 1))
fi

# 2. Plain HTTP is not served (connection refused or timed out, or at least no 2xx/3xx).
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://$host/api/v1/__humo__" || true)"
if [[ "$code" =~ ^[23] ]]; then
  echo "FAIL plain HTTP answered $code"
  failures=$((failures + 1))
else
  echo "ok   plain HTTP not served (code ${code:-none})"
fi

# 3. The nine SSM parameters of the contract exist (plan §7).
count="$(aws ssm get-parameters-by-path --path /urban-alert/plataforma/ --query 'length(Parameters)' --output text)"
if [[ "$count" == "9" ]]; then
  echo "ok   9 SSM parameters under /urban-alert/plataforma/"
else
  echo "FAIL found $count SSM parameters under /urban-alert/plataforma/, expected 9"
  failures=$((failures + 1))
fi

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi
echo "smoke-gateway: all checks passed"
