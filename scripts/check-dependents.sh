#!/usr/bin/env bash
# Lists the resources of other stacks that still use the platform, so the deprovision workflow
# stops before destroying anything (spec RF-012, plan D-009).
# Usage: scripts/check-dependents.sh [--desde-dir DIR] <vpc_id> <api_id>
#   --desde-dir: read the AWS CLI JSON answers from DIR instead of calling AWS (tests).
# Exit codes: 0 no dependents, 1 dependents found, 2 usage error.
set -euo pipefail

dir=""
if [[ "${1:-}" == "--desde-dir" ]]; then
  dir="${2:-}"
  shift 2 || true
fi
if [[ $# -ne 2 || -z "$1" ]]; then
  echo "usage: $0 [--desde-dir DIR] <vpc_id> <api_id>" >&2
  exit 2
fi
vpc="$1"
api="$2"

if [[ -z "$dir" ]]; then
  dir="$(mktemp -d)"
  trap 'rm -rf "$dir"' EXIT
  aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc" --output json >"$dir/security-groups.json"
  aws elbv2 describe-load-balancers --output json >"$dir/load-balancers.json"
  aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$vpc" --output json >"$dir/network-interfaces.json"
  if [[ -n "$api" ]]; then
    aws apigatewayv2 get-routes --api-id "$api" --output json >"$dir/routes.json"
    aws apigatewayv2 get-integrations --api-id "$api" --output json >"$dir/integrations.json"
  else
    echo '{"Items":[]}' >"$dir/routes.json"
    echo '{"Items":[]}' >"$dir/integrations.json"
  fi
fi

# The platform's own resources are excluded: the default security group, the ones tagged Stack=plataforma,
# and the network interfaces of the NAT gateways and the VPC link. The platform creates no routes.
dependents="$(
  jq -r --arg vpc "$vpc" '.SecurityGroups[]
    | select(.VpcId == $vpc and .GroupName != "default")
    | select([(.Tags // [])[] | select(.Key == "Stack" and .Value == "plataforma")] | length == 0)
    | "  - security group \(.GroupId) (\(.GroupName))"' "$dir/security-groups.json"
  jq -r --arg vpc "$vpc" '.LoadBalancers[]
    | select(.VpcId == $vpc)
    | "  - load balancer \(.LoadBalancerName)"' "$dir/load-balancers.json"
  jq -r --arg vpc "$vpc" '.NetworkInterfaces[]
    | select(.VpcId == $vpc and .InterfaceType != "nat_gateway" and .InterfaceType != "api_gateway_managed")
    | "  - network interface \(.NetworkInterfaceId) (\(.InterfaceType): \(.Description // ""))"' "$dir/network-interfaces.json"
  jq -r '.Items[] | "  - gateway route \(.RouteKey)"' "$dir/routes.json"
  jq -r '.Items[] | "  - gateway integration \(.IntegrationId)"' "$dir/integrations.json"
)"

if [[ -z "$dependents" ]]; then
  echo "check-dependents: no other stack uses the VPC $vpc or the gateway $api."
  exit 0
fi

echo "check-dependents: the platform is still in use; nothing was destroyed." >&2
echo "$dependents" >&2
echo "Deprovision the microservices first (their own Deprovision workflows), then run this workflow again." >&2
exit 1
