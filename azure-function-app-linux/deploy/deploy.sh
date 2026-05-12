#!/usr/bin/env bash
# Push the deploy.zip to the Function App provisioned by provision.sh.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE="$DIR/.deploy-state"
ZIP="$DIR/deploy.zip"

[[ -f "$STATE" ]] || { echo "ERROR: $STATE missing — run deploy/provision.sh first" >&2; exit 1; }
[[ -f "$ZIP" ]]   || { echo "ERROR: $ZIP missing — run deploy/build.sh first" >&2; exit 1; }

# shellcheck disable=SC1090
source "$STATE"

echo "==> deploying $ZIP to $APP in $RG"
az functionapp deployment source config-zip \
    -g "$RG" -n "$APP" \
    --src "$ZIP" \
    -o none

echo "==> state:"
az functionapp show -g "$RG" -n "$APP" --query "{name:name, state:state, kind:kind, defaultHostName:defaultHostName}" -o table
echo
echo "tail logs with: az webapp log tail -g $RG -n $APP"
