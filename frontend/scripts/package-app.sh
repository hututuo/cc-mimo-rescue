#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FRONTEND_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
PROJECT_DIR="$(cd -- "${FRONTEND_DIR}/.." && pwd)"
BACKEND_DIR="${PROJECT_DIR}/backend"
APP_NAME="CC MiMo Rescue"
PRODUCT_NAME="CCMimoRescueUI"
BUNDLE_ID="${CC_MIMO_RESCUE_BUNDLE_ID:-dev.cc-mimo-rescue.ui}"
VERSION="${CC_MIMO_RESCUE_VERSION:-0.1.1}"
BUILD="${CC_MIMO_RESCUE_BUILD:-2}"
APPCAST_URL="${CC_MIMO_RESCUE_APPCAST_URL:-https://github.com/hututuo/cc-mimo-rescue/releases/latest/download/appcast.xml}"
PUBLIC_KEY_FILE="${CC_MIMO_RESCUE_SPARKLE_PUBLIC_KEY_FILE:-${FRONTEND_DIR}/Resources/sparkle-public-ed-key.txt}"
APP_DIR="${FRONTEND_DIR}/dist/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
FRAMEWORKS_DIR="${CONTENTS_DIR}/Frameworks"

if [[ ! -f "${BACKEND_DIR}/src/cc_mimo_rescue/__main__.py" ]]; then
  echo "Backend not found at ${BACKEND_DIR}" >&2
  exit 1
fi

cd "${FRONTEND_DIR}"
swift build -c release

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}" "${FRAMEWORKS_DIR}"

cp ".build/release/${PRODUCT_NAME}" "${MACOS_DIR}/${PRODUCT_NAME}"
chmod +x "${MACOS_DIR}/${PRODUCT_NAME}"

SPARKLE_FRAMEWORK="$(find "${FRONTEND_DIR}/.build" -path '*/Sparkle.framework' -type d -print -quit)"
if [[ -n "${SPARKLE_FRAMEWORK}" ]]; then
  rsync -a "${SPARKLE_FRAMEWORK}" "${FRAMEWORKS_DIR}/"
  install_name_tool -add_rpath "@executable_path/../Frameworks" "${MACOS_DIR}/${PRODUCT_NAME}" 2>/dev/null || true
else
  echo "Sparkle.framework was not found in .build artifacts" >&2
  exit 1
fi

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

if [[ ! -f "${PUBLIC_KEY_FILE}" ]]; then
  echo "Sparkle public key not found at ${PUBLIC_KEY_FILE}" >&2
  exit 1
fi
SPARKLE_PUBLIC_KEY="$(tr -d '\n\r' < "${PUBLIC_KEY_FILE}")"

cat > "${CONTENTS_DIR}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${PRODUCT_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleName</key>
  <string>CC MiMo Rescue</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${BUILD}</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>SUFeedURL</key>
  <string>${APPCAST_URL}</string>
  <key>SUPublicEDKey</key>
  <string>${SPARKLE_PUBLIC_KEY}</string>
</dict>
</plist>
PLIST

find "${FRAMEWORKS_DIR}" -type d \( -name '*.xpc' -o -name '*.app' -o -name '*.framework' \) -print0 | while IFS= read -r -d '' item; do
  codesign --force --deep --sign - --preserve-metadata=identifier,entitlements,flags "${item}"
done

codesign --force --sign - \
  --requirements "=designated => identifier \"${BUNDLE_ID}\"" \
  "${APP_DIR}"
codesign --verify --deep --strict --verbose=2 "${APP_DIR}"

echo "Created ${APP_DIR}"
