#!/usr/bin/env bash
# Build the Function App publish artifact with the local .NET 8 SDK.
# Output: deploy/deploy.zip — ready for `az functionapp deployment source config-zip`.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$DIR/src"
OUT="$DIR/deploy/out"
ZIP="$DIR/deploy/deploy.zip"

# Make ~/.dotnet/dotnet visible if it isn't already on PATH.
if ! command -v dotnet >/dev/null 2>&1; then
    export PATH="$HOME/.dotnet:$PATH"
fi
command -v dotnet >/dev/null 2>&1 || {
    echo "ERROR: dotnet not on PATH. Install with:" >&2
    echo "  curl -fsSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel 8.0 --install-dir \"\$HOME/.dotnet\"" >&2
    exit 1
}

rm -rf "$OUT" "$ZIP"
mkdir -p "$OUT"

dotnet publish "$SRC/GabrielOtelDemo.csproj" -c Release -o "$OUT" --nologo

(cd "$OUT" && zip -qr "$ZIP" .)
echo "wrote: $ZIP"
ls -lh "$ZIP"
