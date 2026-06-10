#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CC MiMo Rescue"
VERSION="${CC_MIMO_RESCUE_VERSION:-0.1.1}"
INSTALL_DIR="${INSTALL_DIR:-${HOME}/Applications}"
ZIP_NAME="CC-MiMo-Rescue-${VERSION}-mac.zip"
DOWNLOAD_URL="https://github.com/hututuo/cc-mimo-rescue/releases/download/v${VERSION}/${ZIP_NAME}"

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

echo "Installing ${APP_NAME} ${VERSION}"
echo "Target: ${INSTALL_DIR}"
echo "Privacy: local-only app; no telemetry or upload service."

if [[ ! -x /usr/bin/python3 ]]; then
  echo "Missing /usr/bin/python3. Install Xcode Command Line Tools, then run this installer again." >&2
  echo "Command: xcode-select --install" >&2
  exit 1
fi

mkdir -p "${INSTALL_DIR}"

curl -fL --progress-bar "${DOWNLOAD_URL}" -o "${TMP_DIR}/${ZIP_NAME}"
ditto -x -k "${TMP_DIR}/${ZIP_NAME}" "${TMP_DIR}/app"

if [[ ! -d "${TMP_DIR}/app/${APP_NAME}.app" ]]; then
  echo "Downloaded package does not contain ${APP_NAME}.app" >&2
  exit 1
fi

rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
ditto "${TMP_DIR}/app/${APP_NAME}.app" "${INSTALL_DIR}/${APP_NAME}.app"

# curl-installed apps usually do not carry the browser quarantine flag, but remove
# it if present to avoid the misleading "app is damaged" warning for unsigned builds.
xattr -dr com.apple.quarantine "${INSTALL_DIR}/${APP_NAME}.app" 2>/dev/null || true

echo
echo "Installed: ${INSTALL_DIR}/${APP_NAME}.app"
echo "Opening ${APP_NAME}..."
open "${INSTALL_DIR}/${APP_NAME}.app"
