#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FRONTEND_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
APP_NAME="CC MiMo Rescue"
VERSION="${CC_MIMO_RESCUE_VERSION:-0.1.1}"
DIST_DIR="${FRONTEND_DIR}/dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
DMG_NAME="CC-MiMo-Rescue-${VERSION}.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"
STAGING_DIR="${DIST_DIR}/dmg-staging"

if [[ "${CC_MIMO_RESCUE_SKIP_PACKAGE_APP:-0}" != "1" ]]; then
  "${SCRIPT_DIR}/package-app.sh"
fi

rm -rf "${STAGING_DIR}" "${DMG_PATH}"
mkdir -p "${STAGING_DIR}"

cp -R "${APP_DIR}" "${STAGING_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGING_DIR}/Applications"

hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

hdiutil verify "${DMG_PATH}"

rm -rf "${STAGING_DIR}"

echo "Created ${DMG_PATH}"
