#!/usr/bin/env bash
set -euo pipefail

echo "=================================================="
echo "  Building Universal macOS Release: StorageCleaner"
echo "=================================================="

WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${WORKSPACE_DIR}/dist"
APP_BUNDLE="${DIST_DIR}/StorageCleaner.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
DMG_PATH="${DIST_DIR}/StorageCleaner.dmg"

rm -rf "${DIST_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

echo "[1/6] Compiling arm64 (Apple Silicon) target..."
swift build -c release --triple arm64-apple-macosx14.0 --scratch-path "${WORKSPACE_DIR}/.build/arm64"

echo "[2/6] Compiling x86_64 (Intel) target..."
swift build -c release --triple x86_64-apple-macosx14.0 --scratch-path "${WORKSPACE_DIR}/.build/x86_64"

ARM64_BIN="$(find "${WORKSPACE_DIR}/.build/arm64" -type f -name "StorageCleaner" | grep -v "dSYM" | head -n 1)"
X86_BIN="$(find "${WORKSPACE_DIR}/.build/x86_64" -type f -name "StorageCleaner" | grep -v "dSYM" | head -n 1)"

echo "[3/6] Merging into Universal 2 binary with lipo..."
lipo -create "${ARM64_BIN}" "${X86_BIN}" -output "${MACOS_DIR}/StorageCleaner"
chmod +x "${MACOS_DIR}/StorageCleaner"

echo "Binary Architecture Verification:"
lipo -info "${MACOS_DIR}/StorageCleaner"
file "${MACOS_DIR}/StorageCleaner"

echo "[4/6] Creating Info.plist..."
cat << 'EOF' > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>StorageCleaner</string>
    <key>CFBundleIdentifier</key>
    <string>com.localfirst.storagecleaner</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>StorageCleaner</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
EOF

echo "[5/6] Code signing application bundle..."
# Ad-hoc sign for local execution; Developer ID certificate can be passed via SIGN_IDENTITY env var
SIGN_ID="${SIGN_IDENTITY:--}"
codesign --force --deep --sign "${SIGN_ID}" "${APP_BUNDLE}"

echo "Signature Verification:"
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"

echo "[6/6] Generating distributable DMG..."
rm -f "${DMG_PATH}"
hdiutil create -volname "StorageCleaner" -srcfolder "${APP_BUNDLE}" -ov -format UDZO "${DMG_PATH}"

echo "Verifying DMG:"
hdiutil verify "${DMG_PATH}"

echo "=================================================="
echo "  Build & Packaging Succeeded!"
echo "  Bundle: ${APP_BUNDLE}"
echo "  DMG:    ${DMG_PATH}"
echo "=================================================="
