#!/usr/bin/env bash
# Runs a workflow of another UrbanAlert repository on main and waits for its result.
# Usage: scripts/disparar-y-esperar.sh <repo> <workflow file> [input=value ...]
#   e.g. scripts/disparar-y-esperar.sh urban-alert-usuarios pausar.yml confirm=urban-alert-usuarios
# Needs GH_TOKEN with Actions read and write on <repo> (the GITHUB_TOKEN of a run only reaches its own repo).
# Exit 0 when the dispatched run ends in success; otherwise the exit code of `gh run watch`.
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <repo> <workflow file> [input=value ...]" >&2
  exit 2
fi
repo="${ORG:-Unal-Team-C}/$1"
workflow="$2"
shift 2

campos=()
for entrada in "$@"; do
  campos+=(-f "$entrada")
done

# Runs created before this second are not ours (a dispatch returns no run id).
desde="$(date -u +%s)"
gh workflow run "$workflow" --repo "$repo" --ref main ${campos[@]+"${campos[@]}"}

run_id=""
for _ in $(seq 1 "${INTENTOS_BUSQUEDA:-24}"); do
  run_id="$(gh run list --repo "$repo" --workflow "$workflow" --event workflow_dispatch --limit 10 \
    --json databaseId,createdAt |
    jq -r --argjson desde "$((desde - 5))" \
      '[.[] | select((.createdAt | fromdateiso8601) >= $desde)] | sort_by(.createdAt) | .[0].databaseId // empty')"
  [[ -n "$run_id" ]] && break
  sleep "${ESPERA_BUSQUEDA_S:-5}"
done

if [[ -z "$run_id" ]]; then
  echo "::error::$repo: the run of $workflow did not appear after the dispatch." >&2
  exit 1
fi

url="https://github.com/$repo/actions/runs/$run_id"
echo "$repo: $workflow → $url"
if gh run watch "$run_id" --repo "$repo" --exit-status --interval "${INTERVALO_S:-30}" >/dev/null; then
  echo "ok   $repo: $workflow succeeded ($url)"
else
  code=$?
  echo "::error::$repo: $workflow failed ($url)" >&2
  exit "$code"
fi
