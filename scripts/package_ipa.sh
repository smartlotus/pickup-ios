#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:?Usage: package_ipa.sh <path/to/Pickup.app> <output.ipa>}"
OUT_IPA="${2:?Usage: package_ipa.sh <path/to/Pickup.app> <output.ipa>}"

case "$OUT_IPA" in
  /*) ABS_OUT_IPA="$OUT_IPA" ;;
  *)  ABS_OUT_IPA="$PWD/$OUT_IPA" ;;
esac

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/Payload"
cp -R "$APP_PATH" "$TMP_DIR/Payload/"
rm -f "$ABS_OUT_IPA"
mkdir -p "$(dirname "$ABS_OUT_IPA")"

(
  cd "$TMP_DIR"
  zip -qry -9 "$ABS_OUT_IPA" Payload
)

echo "Packaged IPA: $ABS_OUT_IPA ($(du -h "$ABS_OUT_IPA" | awk '{print $1}'))"
