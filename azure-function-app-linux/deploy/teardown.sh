#!/usr/bin/env bash
# Surgical removal of ONLY the resources provision.sh created.
# Identified by the suffix saved in deploy/.deploy-state. NEVER deletes the resource group
# or the shared App Service plan. Asks for explicit confirmation before deleting.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE="$DIR/.deploy-state"

[[ -f "$STATE" ]] || { echo "ERROR: $STATE missing — nothing to tear down" >&2; exit 1; }
# shellcheck disable=SC1090
source "$STATE"

echo "About to DELETE the following resources from $RG (and nothing else):"
echo "  function app: $APP"
echo "  storage:      $SA"
echo
echo "Will NOT touch: the resource group, the plan, or any other resource in $RG."
echo
read -r -p "Type the suffix '$SUFFIX' to confirm: " confirm
[[ "$confirm" == "$SUFFIX" ]] || { echo "abort"; exit 1; }

# Re-verify each resource is still tagged as created-by us before deleting.
APP_TAG="$(az functionapp show -g "$RG" -n "$APP" --query "tags.\"created-by\"" -o tsv 2>/dev/null || echo "")"
if [[ "$APP_TAG" != "function_app_demo_linux" ]]; then
    echo "ERROR: $APP is missing the expected 'created-by=function_app_demo_linux' tag — refusing to delete" >&2
    exit 1
fi
SA_TAG="$(az storage account show -g "$RG" -n "$SA" --query "tags.\"created-by\"" -o tsv 2>/dev/null || echo "")"
if [[ "$SA_TAG" != "function_app_demo_linux" ]]; then
    echo "ERROR: $SA is missing the expected 'created-by=function_app_demo_linux' tag — refusing to delete" >&2
    exit 1
fi

echo "==> deleting $APP"
az functionapp delete -g "$RG" -n "$APP" -o none

echo "==> deleting $SA"
az storage account delete -g "$RG" -n "$SA" --yes -o none

rm -f "$STATE"
echo "done."
