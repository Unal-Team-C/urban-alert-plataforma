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

# Pause scripts, with fake aws and gh commands first in PATH (FAKE_* variables choose their answers).
FAKES="$(mktemp -d)"
trap 'rm -rf "$FAKES"' EXIT
cat >"$FAKES/aws" <<'EOF'
#!/usr/bin/env bash
echo "aws $*" >>"$FAKE_LOG"
case "$1 $2" in
  "ssm get-parameter")
    case "$FAKE_SSM" in
      missing) echo "An error occurred (ParameterNotFound) when calling the GetParameter operation" >&2; exit 254 ;;
      denied) echo "An error occurred (AccessDeniedException) when calling the GetParameter operation" >&2; exit 254 ;;
      *) echo "$FAKE_SSM" ;;
    esac ;;
  "rds describe-db-instances") printf '%s\n' "$FAKE_RDS" ;;
  "docdb describe-db-clusters") printf '%s\n' "$FAKE_DOCDB" ;;
esac
EOF
cat >"$FAKES/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >>"$FAKE_LOG"
case "$1 $2" in
  "run list") echo "[{\"databaseId\": 4242, \"createdAt\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}]" ;;
  "run watch") exit "${FAKE_WATCH_EXIT:-0}" ;;
esac
EOF
chmod +x "$FAKES/aws" "$FAKES/gh"
export FAKE_LOG="$FAKES/log" ESPERA_BUSQUEDA_S=0 INTENTOS_BUSQUEDA=2 INTERVALO_S=1
fake() { env PATH="$FAKES:$PATH" "$@"; }

estado="$ROOT/scripts/estado-pausa.sh"
expect "pause state: true"                   0 "true"                fake env FAKE_SSM=true bash "$estado"
expect "pause state: missing means false"    0 "false"               fake env FAKE_SSM=missing bash "$estado"
expect "pause state: access denied fails"    1 "AccessDenied"        fake env FAKE_SSM=denied bash "$estado"
expect "pause state: unexpected value fails" 1 "Unexpected value"    fake env FAKE_SSM=quizas bash "$estado"

parar="$ROOT/scripts/detener-bases.sh"
: >"$FAKE_LOG"
expect "stop: RDS and DocumentDB running"    0 "stopped in this run: 3" fake env FAKE_RDS="urban-alert-usuarios-db	urban-alert-reportes-db" FAKE_DOCDB="urban-alert-multimedia-docdb" bash "$parar"
expect "stop: each one stopped by its API"   0 ""                    grep -q "docdb stop-db-cluster --db-cluster-identifier urban-alert-multimedia-docdb" "$FAKE_LOG"
expect "stop: nothing running"               0 "stopped in this run: 0" fake env FAKE_RDS="" FAKE_DOCDB="" bash "$parar"

disparar="$ROOT/scripts/disparar-y-esperar.sh"
: >"$FAKE_LOG"
expect "dispatch: run succeeds"              0 "runs/4242"           fake bash "$disparar" urban-alert-usuarios pausar.yml confirm=urban-alert-usuarios
expect "dispatch: runs on main with inputs"  0 ""                    grep -q -- "--ref main -f confirm=urban-alert-usuarios" "$FAKE_LOG"
expect "dispatch: failed run fails"          1 "failed"              fake env FAKE_WATCH_EXIT=1 bash "$disparar" urban-alert-usuarios pausar.yml
expect "dispatch: usage without arguments"   2 "usage"               fake bash "$disparar"

if [[ "$failures" -gt 0 ]]; then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
