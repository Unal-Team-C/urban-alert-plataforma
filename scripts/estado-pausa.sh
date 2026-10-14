#!/usr/bin/env bash
# Prints the pause state of the platform: "true" or "false" (SSM /urban-alert/plataforma/pausada).
# A platform provisioned before the parameter existed has no parameter yet: that counts as "false".
# Any other error (credentials, permissions) fails, so a workflow never assumes the wrong state.
# Usage: scripts/estado-pausa.sh   (needs AWS credentials)
set -euo pipefail

nombre="/urban-alert/plataforma/pausada"
err="$(mktemp)"
trap 'rm -f "$err"' EXIT

if valor="$(aws ssm get-parameter --name "$nombre" --query Parameter.Value --output text 2>"$err")"; then
  case "$valor" in
    true | false) echo "$valor" ;;
    *)
      echo "Unexpected value '$valor' in $nombre (expected true or false)." >&2
      exit 1
      ;;
  esac
elif grep -q ParameterNotFound "$err"; then
  echo false
else
  cat "$err" >&2
  exit 1
fi
