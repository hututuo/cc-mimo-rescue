#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FRONTEND_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
PROJECT_DIR="$(cd -- "${FRONTEND_DIR}/.." && pwd)"
BACKEND_DIR="${PROJECT_DIR}/backend"
APP_NAME="CC MiMo Rescue"
APP_DIR="${FRONTEND_DIR}/dist/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

if [[ ! -f "${BACKEND_DIR}/src/cc_mimo_rescue/__main__.py" ]]; then
  echo "Backend not found at ${BACKEND_DIR}" >&2
  exit 1
fi

cd "${FRONTEND_DIR}"
swift build -c release

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp ".build/release/CCMimoRescueUI" "${MACOS_DIR}/CCMimoRescueUI"
chmod +x "${MACOS_DIR}/CCMimoRescueUI"

if [[ -f "${FRONTEND_DIR}/Resources/AppIcon.icns" ]]; then
  cp "${FRONTEND_DIR}/Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

rsync -a \
  --exclude '__pycache__' \
  --exclude '*.pyc' \
  --exclude '.DS_Store' \
  --exclude '.pytest_cache' \
  --exclude '.mypy_cache' \
  --exclude '.ruff_cache' \
  --exclude '*.egg-info' \
  "${BACKEND_DIR}/" \
  "${RESOURCES_DIR}/backend/"

cat > "${CONTENTS_DIR}/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>CCMimoRescueUI</string>
  <key>CFBundleIdentifier</key>
  <string>dev.cc-mimo-rescue.ui</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleName</key>
  <string>CC MiMo Rescue</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo "Created ${APP_DIR}"
