#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FRONTEND_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
PROJECT_DIR="$(cd -- "${FRONTEND_DIR}/.." && pwd)"

APP_NAME="CC MiMo Rescue"
APP_SLUG="CC-MiMo-Rescue"
VERSION="${CC_MIMO_RESCUE_VERSION:-0.1.1}"
BUILD="${CC_MIMO_RESCUE_BUILD:-2}"
BUNDLE_ID="${CC_MIMO_RESCUE_BUNDLE_ID:-dev.cc-mimo-rescue.ui}"
DIST_DIR="${FRONTEND_DIR}/dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
RELEASE_DIR="${DIST_DIR}/release-v${VERSION}"
APPCAST_STAGE="${RELEASE_DIR}/appcast-stage"
DOWNLOAD_URL_PREFIX="${CC_MIMO_RESCUE_DOWNLOAD_URL_PREFIX:-https://github.com/hututuo/cc-mimo-rescue/releases/download/v${VERSION}/}"
SPARKLE_PRIVATE_KEY_FILE="${SPARKLE_PRIVATE_KEY_FILE:-${HOME}/.config/cc-mimo-rescue/sparkle-ed25519-private.key}"
VERSIONED_ZIP="${APP_SLUG}-${VERSION}-macos-arm64.app.zip"
COMPAT_ZIP="${APP_SLUG}-${VERSION}-mac.zip"
DMG_NAME="${APP_SLUG}-${VERSION}.dmg"
CHECKSUMS_NAME="SHA256SUMS-v${VERSION}.txt"
RELEASE_NOTES_SOURCE="${PROJECT_DIR}/docs/releases/v${VERSION}.md"
APPCAST_NOTES="${APPCAST_STAGE}/${APP_SLUG}-${VERSION}-macos-arm64.app.md"

if [[ ! -f "${SPARKLE_PRIVATE_KEY_FILE}" ]]; then
  echo "Sparkle private key not found: ${SPARKLE_PRIVATE_KEY_FILE}" >&2
  echo "Set SPARKLE_PRIVATE_KEY_FILE or generate the key under ~/.config/cc-mimo-rescue." >&2
  exit 1
fi

if [[ ! -f "${RELEASE_NOTES_SOURCE}" ]]; then
  echo "Release notes not found: ${RELEASE_NOTES_SOURCE}" >&2
  exit 1
fi

rm -rf "${RELEASE_DIR}"
mkdir -p "${RELEASE_DIR}" "${APPCAST_STAGE}"

export CC_MIMO_RESCUE_VERSION="${VERSION}"
export CC_MIMO_RESCUE_BUILD="${BUILD}"
export CC_MIMO_RESCUE_BUNDLE_ID="${BUNDLE_ID}"
"${SCRIPT_DIR}/package-app.sh"

ditto -c -k --sequesterRsrc --keepParent "${APP_DIR}" "${APPCAST_STAGE}/${VERSIONED_ZIP}"
cp "${RELEASE_NOTES_SOURCE}" "${APPCAST_NOTES}"

SPARKLE_BIN="${FRONTEND_DIR}/.build/artifacts/sparkle/Sparkle/bin"
"${SPARKLE_BIN}/generate_appcast" \
  --ed-key-file "${SPARKLE_PRIVATE_KEY_FILE}" \
  --download-url-prefix "${DOWNLOAD_URL_PREFIX}" \
  --embed-release-notes \
  "${APPCAST_STAGE}"

cp "${APPCAST_STAGE}/${VERSIONED_ZIP}" "${RELEASE_DIR}/${VERSIONED_ZIP}"
cp "${APPCAST_STAGE}/${VERSIONED_ZIP}" "${RELEASE_DIR}/${COMPAT_ZIP}"
cp "${APPCAST_STAGE}/appcast.xml" "${RELEASE_DIR}/appcast.xml"
cp "${RELEASE_NOTES_SOURCE}" "${RELEASE_DIR}/RELEASE_NOTES-v${VERSION}.md"

CC_MIMO_RESCUE_SKIP_PACKAGE_APP=1 "${SCRIPT_DIR}/package-dmg.sh"
cp "${DIST_DIR}/${DMG_NAME}" "${RELEASE_DIR}/${DMG_NAME}"

(
  cd "${RELEASE_DIR}"
  shasum -a 256 "${VERSIONED_ZIP}" "${COMPAT_ZIP}" "${DMG_NAME}" "appcast.xml" > "${CHECKSUMS_NAME}"
)

codesign --verify --deep --strict --verbose=2 "${APP_DIR}"
codesign -d -r- "${APP_DIR}"
hdiutil verify "${RELEASE_DIR}/${DMG_NAME}"

echo "Release artifacts:"
echo "${RELEASE_DIR}/${VERSIONED_ZIP}"
echo "${RELEASE_DIR}/${COMPAT_ZIP}"
echo "${RELEASE_DIR}/${DMG_NAME}"
echo "${RELEASE_DIR}/appcast.xml"
echo "${RELEASE_DIR}/${CHECKSUMS_NAME}"
