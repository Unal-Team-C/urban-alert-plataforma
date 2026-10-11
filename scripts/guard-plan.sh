#!/usr/bin/env bash
# Fails when a Terraform plan deletes or replaces a resource the microservices depend on
# (spec RF-013, constitution P4, plan D-008), unless permitir_reemplazo_compartido = true was committed.
# Usage: scripts/guard-plan.sh <plan.json>   (plan.json = terraform show -json tfplan)
set -euo pipefail

if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "usage: $0 <plan.json>" >&2
  exit 2
fi
plan="$1"

# Shared resources: the network, the gateway, the VPC link and the SSM contract.
protected='^(aws_vpc\.this|aws_subnet\.privada\[[0-9]+\]|aws_apigatewayv2_api\.this|aws_apigatewayv2_stage\.default|aws_apigatewayv2_vpc_link\.this|aws_security_group\.vpc_link|aws_ssm_parameter\.contrato\[.*\])$'

# One "  - address (actions)" line per blocked change; plain string so it also runs on macOS bash 3.2.
blocked="$(jq -r --arg re "$protected" '
  .resource_changes // []
  | map(select((.change.actions | index("delete")) and (.address | test($re))))
  | .[] | "  - \(.address) (\(.change.actions | join(", ")))"' "$plan")"

if [[ -z "$blocked" ]]; then
  echo "guard-plan: no shared resource is deleted or replaced."
  exit 0
fi

allowed="$(jq -r '.variables.permitir_reemplazo_compartido.value // false' "$plan")"
if [[ "$allowed" == "true" ]]; then
  echo "guard-plan: permitir_reemplazo_compartido = true; allowing changes to shared resources:"
  echo "$blocked"
  exit 0
fi

echo "guard-plan: the plan deletes or replaces shared resources used by the microservices:" >&2
echo "$blocked" >&2
echo "Set permitir_reemplazo_compartido = true in infra/plataforma/terraform.tfvars, in a commit, if this is intended." >&2
exit 1
