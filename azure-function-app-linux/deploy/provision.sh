#!/usr/bin/env bash
# Provision the Linux Function App in $RG.
# Reuses the existing $PLAN (Linux App Service Plan) — does NOT create a new plan.
# Touches ONLY the resource group named in $RG. Fails closed if the RG doesn't exist.
#
# Why App Service Plan, not Consumption (Y1)?
#   On Linux Consumption, the dotnet-isolated placeholder pre-warms a worker process
#   that doesn't fully re-execute Program.cs on specialization, leading to OTel
#   listener registration that's flaky/disposed across cold starts. App Service Plan
#   (B1+) gives us a stable, always-on worker — the OTel listeners stay registered
#   for the process lifetime. See README "Gotchas" for the diagnostic story.
set -euo pipefail

RG="${RG:-gabriel-rg}"
LOCATION="${LOCATION:-eastus}"
PLAN="${PLAN:-gabriel-dt-demo-plan}"   # B1 Linux, must already exist in $RG
PREFIX="${PREFIX:-gabriel-otel-demo}"
SA_PREFIX="${SA_PREFIX:-gabotelfuncsa}"

DT_OTLP_ENDPOINT="${DT_OTLP_ENDPOINT:?Set DT_OTLP_ENDPOINT, e.g. https://ktn7285h.sprint.dynatracelabs.com/api/v2/otlp}"
DT_API_TOKEN="${DT_API_TOKEN:?Set DT_API_TOKEN (dt0c01.... with openTelemetryTrace.ingest, metrics.ingest)}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE="$DIR/.deploy-state"

# Sanity: confirm the RG exists in the current subscription before doing anything.
if ! az group show -n "$RG" -o none 2>/dev/null; then
    echo "ERROR: resource group '$RG' not found in current subscription" >&2
    az account show --query "{name:name, id:id}" -o table >&2 || true
    exit 1
fi

# Sanity: the plan must already exist — we do NOT create one.
if ! az appservice plan show -g "$RG" -n "$PLAN" -o none 2>/dev/null; then
    echo "ERROR: plan '$PLAN' not found in '$RG' — refusing to create a plan automatically" >&2
    echo "       Either create it manually (e.g. 'az appservice plan create ... --sku B1 --is-linux')" >&2
    echo "       or set PLAN=<existing-plan-name>" >&2
    exit 1
fi

# Generate a stable random suffix and persist it so teardown can find what we created.
if [[ -f "$STATE" ]]; then
    # shellcheck disable=SC1090
    source "$STATE"
    echo "reusing existing deployment state: SUFFIX=$SUFFIX"
else
    SUFFIX="$(openssl rand -hex 2)"
    cat > "$STATE" <<EOF
RG="$RG"
PLAN="$PLAN"
SUFFIX="$SUFFIX"
SA="${SA_PREFIX}${SUFFIX}"
APP="${PREFIX}-func-${SUFFIX}"
EOF
    echo "wrote: $STATE (SUFFIX=$SUFFIX)"
fi

SA="${SA_PREFIX}${SUFFIX}"
APP="${PREFIX}-func-${SUFFIX}"

echo "==> creating storage account $SA in $RG/$LOCATION"
az storage account create \
    -g "$RG" -n "$SA" -l "$LOCATION" \
    --sku Standard_LRS --kind StorageV2 \
    --allow-blob-public-access false \
    --tags purpose=otel-demo owner=gabriel created-by=function_app_demo_linux \
    -o none

echo "==> creating function app $APP on plan $PLAN (Linux, .NET 8 isolated)"
az functionapp create \
    -g "$RG" -n "$APP" \
    --plan "$PLAN" \
    --storage-account "$SA" \
    --runtime dotnet-isolated \
    --runtime-version 8 \
    --functions-version 4 \
    --os-type Linux \
    --tags purpose=otel-demo owner=gabriel created-by=function_app_demo_linux \
    --disable-app-insights true \
    -o none

echo "==> setting OTel app settings (token in app settings, never in any committed file)"
RESOURCE_ID="$(az functionapp show -g "$RG" -n "$APP" --query id -o tsv)"
az functionapp config appsettings set \
    -g "$RG" -n "$APP" \
    --settings \
        "OTEL_EXPORTER_OTLP_ENDPOINT=$DT_OTLP_ENDPOINT" \
        "OTEL_EXPORTER_OTLP_HEADERS=Authorization=Api-Token $DT_API_TOKEN" \
        "OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf" \
        "OTEL_SERVICE_NAME=gabriel-otel-demo" \
        "OTEL_RESOURCE_ATTRIBUTES=azure.resource.id=$RESOURCE_ID,deployment.environment=demo" \
    -o none

echo
echo "provisioned:"
echo "  storage:      $SA"
echo "  function app: $APP"
echo "  resource id:  $RESOURCE_ID"
echo
echo "next: bash deploy/build.sh && bash deploy/deploy.sh"
