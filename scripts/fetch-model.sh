#!/usr/bin/env bash
# Downloads the built-in open-source model (Apache-2.0) bundled in the full ReyForge IPA.
# Usage: scripts/fetch-model.sh [dest-dir]
set -euo pipefail
DEST="${1:-App/Builder/Resources/Models}"
NAME="${REYFORGE_MODEL_FILE:-Qwen3.5-2B-Q4_K_M.gguf}"
URL="${REYFORGE_MODEL_URL:-https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/Qwen3.5-2B-Q4_K_M.gguf}"
MIN_BYTES="${REYFORGE_MODEL_MIN_BYTES:-500000000}"
mkdir -p "$DEST"
OUT="$DEST/$NAME"
size() { stat -f%z "$1" 2>/dev/null || stat -c%s "$1"; }
if [ -f "$OUT" ] && [ "$(size "$OUT")" -ge "$MIN_BYTES" ]; then
  echo "Model already present: $OUT ($(size "$OUT") bytes)"; exit 0
fi
for i in 1 2 3 4 5; do
  if curl -fL --retry 3 -C - -o "$OUT.part" "$URL"; then break; fi
  echo "Download interrupted, retrying ($i)…"; sleep 5
done
mv "$OUT.part" "$OUT"
[ "$(size "$OUT")" -ge "$MIN_BYTES" ] || { echo "Model download looks incomplete"; exit 1; }
head -c 4 "$OUT" | grep -q GGUF || { echo "Not a GGUF file"; exit 1; }
echo "Model ready: $OUT ($(size "$OUT") bytes)"
