#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:?Usage: package_ipa.sh <path/to/PickupIOS.app> <output.ipa>}"
OUT_IPA="${2:?Usage: package_ipa.sh <path/to/PickupIOS.app> <output.ipa>}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/Payload"
cp -R "$APP_PATH" "$TMP_DIR/Payload/"
rm -f "$OUT_IPA"
mkdir -p "$(dirname "$OUT_IPA")"

(
  cd "$TMP_DIR"
  zip -qry -9 "$OLDPWD/$OUT_IPA" Payload
)

echo "Packaged IPA: $OUT_IPA ($(du -h "$OUT_IPA" | awk '{print $1}'))"
