#!/usr/bin/env bash
# Tests for scripts/guard-plan.sh and scripts/check-dependents.sh against JSON fixtures (no AWS calls).
# Usage: bash scripts/tests/run.sh   (needs jq)
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIX="$ROOT/scripts/tests/fixtures"
VPC="vpc-0plataforma"
API="api0plataforma"
failures=0

# expect <name> <expected exit code> <text the output must contain, or ""> <command...>
expect() {
  local name="$1" want="$2" text="$3"
  shift 3
  local out code
  out="$("$@" 2>&1)"
  code=$?
  if [[ "$code" -ne "$want" ]]; then
    echo "FAIL $name: exit $code, expected $want"
    printf '    %s\n' "$out"
    failures=$((failures + 1))
  elif [[ -n "$text" && "$out" != *"$text"* ]]; then
    echo "FAIL $name: output does not contain '$text'"
    printf '    %s\n' "$out"
    failures=$((failures + 1))
  else
    echo "ok   $name"
  fi
}

guard="$ROOT/scripts/guard-plan.sh"
expect "guard: no shared changes"            0 ""                    bash "$guard" "$FIX/plan-sin-cambios.json"
expect "guard: VPC replacement blocked"      1 "aws_vpc.this"        bash "$guard" "$FIX/plan-reemplaza-vpc.json"
expect "guard: subnet replacement listed"    1 "aws_subnet.privada[1]" bash "$guard" "$FIX/plan-reemplaza-vpc.json"
expect "guard: replacement allowed by flag"  0 ""                    bash "$guard" "$FIX/plan-reemplaza-vpc-permitido.json"
expect "guard: SSM parameter deletion"       1 "aws_ssm_parameter"   bash "$guard" "$FIX/plan-borra-parametro.json"

deps="$ROOT/scripts/check-dependents.sh"
expect "deps: empty platform"                0 ""                    bash "$deps" --desde-dir "$FIX/deps-vacio" "$VPC" "$API"
expect "deps: foreign security group"        1 "sg-0geoespacial"     bash "$deps" --desde-dir "$FIX/deps-sg-ajeno" "$VPC" "$API"
expect "deps: load balancer in the VPC"      1 "ecs-express-gateway-alb-1" bash "$deps" --desde-dir "$FIX/deps-alb" "$VPC" "$API"
expect "deps: route in the gateway"          1 "GET /api/v1/geoespacial/reports" bash "$deps" --desde-dir "$FIX/deps-ruta" "$VPC" "$API"
expect "deps: integration in the gateway"    1 "i1"                  bash "$deps" --desde-dir "$FIX/deps-ruta" "$VPC" "$API"
expect "deps: task network interface"        1 "eni-0tarea"          bash "$deps" --desde-dir "$FIX/deps-eni-tarea" "$VPC" "$API"

if [[ "$failures" -gt 0 ]]; then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
