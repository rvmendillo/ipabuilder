#!/usr/bin/env bash
# Downloads the prebuilt llama.cpp XCFramework (MIT) used by the built-in on-device model.
# Usage: scripts/fetch-llama.sh [dest-dir]   (env LLAMA_TAG=bNNNN to pin, default: latest with an xcframework)
set -euo pipefail
DEST="${1:-Vendor}"
TAG="${LLAMA_TAG:-latest}"
mkdir -p "$DEST"
if [ -d "$DEST/llama.xcframework" ]; then
  echo "llama.xcframework already present in $DEST"; exit 0
fi
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
python3 - "$TAG" "$WORK/asset.txt" <<'PY'
import json, os, sys, urllib.request
tag, out = sys.argv[1], sys.argv[2]
base = "https://api.github.com/repos/ggml-org/llama.cpp/releases"
headers = {"Accept": "application/vnd.github+json", "User-Agent": "reyforge-ci"}
tok = os.environ.get("GITHUB_TOKEN")
if tok: headers["Authorization"] = "Bearer " + tok
def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers)) as r:
        return json.load(r)
releases = [get(f"{base}/tags/{tag}")] if tag != "latest" else get(f"{base}?per_page=15")
for rel in releases:
    for a in rel.get("assets", []):
        if "xcframework" in a["name"] and a["name"].endswith(".zip"):
            open(out, "w").write(f'{rel["tag_name"]} {a["browser_download_url"]}\n')
            print("llama.cpp", rel["tag_name"], "->", a["name"])
            sys.exit(0)
sys.exit("No llama.cpp release with an xcframework asset found")
PY
read -r RESOLVED URL < "$WORK/asset.txt"
curl -fL --retry 4 --retry-delay 3 -o "$WORK/llama.zip" "$URL"
unzip -q "$WORK/llama.zip" -d "$WORK/x"
FW="$(find "$WORK/x" -type d -name 'llama.xcframework' | head -1)"
[ -n "$FW" ] || { echo "llama.xcframework not found in archive"; exit 1; }
mv "$FW" "$DEST/llama.xcframework"
echo "$RESOLVED" > "$DEST/llama.version"
echo "Installed llama.xcframework ($RESOLVED) into $DEST"
ls "$DEST/llama.xcframework"
