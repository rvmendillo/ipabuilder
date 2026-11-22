#!/usr/bin/env bash
# Signs an unsigned IPA with your own certificate (.p12) and provisioning profile using codesign (macOS).
# Usage: scripts/sign-ipa.sh in.ipa out.ipa cert.p12 p12-password profile.mobileprovision [bundle-id]
# If bundle-id is omitted: an explicit profile's App ID is used, or the app's own id for wildcard profiles.
set -euo pipefail
IN="$1"; OUT="$2"; P12="$3"; PASS="$4"; PROFILE="$5"; WANT_ID="${6:-}"
WORK="$(mktemp -d)"
KC="$WORK/signing.keychain-db"; KCPASS="$(uuidgen)"
cleanup() { security delete-keychain "$KC" >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap cleanup EXIT

security create-keychain -p "$KCPASS" "$KC"
security set-keychain-settings -lut 3600 "$KC"
security unlock-keychain -p "$KCPASS" "$KC"
security import "$P12" -k "$KC" -P "$PASS" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KCPASS" "$KC" >/dev/null
security list-keychains -d user -s "$KC" $(security list-keychains -d user | tr -d '"')
IDENTITY="$(security find-identity -v -p codesigning "$KC" | awk 'NR==1 && $2 ~ /^[0-9A-F]{40}$/ {print $2}')"
[ -n "$IDENTITY" ] || { echo "No code signing identity found in the .p12"; security find-identity -v "$KC"; exit 1; }
echo "Signing identity: $(security find-identity -v -p codesigning "$KC" | head -1)"

security cms -D -i "$PROFILE" > "$WORK/profile.plist"
APPID="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$WORK/profile.plist")"
TEAM="$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$WORK/profile.plist")"
PROFILE_ID="${APPID#*.}"
echo "Profile: $(/usr/libexec/PlistBuddy -c 'Print :Name' "$WORK/profile.plist") — App ID $APPID"

unzip -q "$IN" -d "$WORK/x"
APP="$(find "$WORK/x/Payload" -maxdepth 1 -name '*.app' | head -1)"
CURRENT_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"
if [ -n "$WANT_ID" ]; then BUNDLE_ID="$WANT_ID"
elif [ "$PROFILE_ID" = "*" ]; then BUNDLE_ID="$CURRENT_ID"
elif [[ "$PROFILE_ID" == *".*" ]]; then BUNDLE_ID="${PROFILE_ID%.*}.$(echo "$CURRENT_ID" | awk -F. '{print $NF}')"
else BUNDLE_ID="$PROFILE_ID"; fi
echo "Bundle ID: $CURRENT_ID -> $BUNDLE_ID"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Info.plist"

/usr/libexec/PlistBuddy -x -c 'Print :Entitlements' "$WORK/profile.plist" > "$WORK/ent.plist"
/usr/libexec/PlistBuddy -c "Set :application-identifier $TEAM.$BUNDLE_ID" "$WORK/ent.plist"
cp "$PROFILE" "$APP/embedded.mobileprovision"
rm -rf "$APP/_CodeSignature"

# Sign nested code first (frameworks, dylibs, extensions), then the app.
find "$APP" -depth \( -name '*.framework' -o -name '*.dylib' -o -name '*.appex' \) -print0 | while IFS= read -r -d '' item; do
  codesign --force --sign "$IDENTITY" --keychain "$KC" --timestamp=none --generate-entitlement-der "$item"
done
codesign --force --sign "$IDENTITY" --keychain "$KC" --timestamp=none --generate-entitlement-der --entitlements "$WORK/ent.plist" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

mkdir -p "$(dirname "$OUT")"
OUT_ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
rm -f "$OUT_ABS"
(cd "$WORK/x" && zip -qry -X "$OUT_ABS" Payload)
echo "Signed IPA: $OUT_ABS"
echo "bundle_id=$BUNDLE_ID" >> "${GITHUB_OUTPUT:-/dev/null}"
