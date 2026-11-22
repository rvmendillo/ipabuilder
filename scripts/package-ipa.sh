#!/usr/bin/env bash
# Wraps a built .app into an .ipa (Payload/App.app). Optional: --lite removes bundled models.
# Usage: scripts/package-ipa.sh path/to/App.app out.ipa [--lite]
set -euo pipefail
APP="$1"; OUT="$2"; LITE="${3:-}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/Payload"
ditto "$APP" "$WORK/Payload/$(basename "$APP")"
if [ "$LITE" = "--lite" ]; then
  find "$WORK/Payload" -name '*.gguf' -delete
fi
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
OUT_ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
(cd "$WORK" && zip -qry -X "$OUT_ABS" Payload)
echo "Packaged $(basename "$OUT"): $(du -h "$OUT_ABS" | cut -f1)"
