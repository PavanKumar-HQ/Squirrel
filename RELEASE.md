# Release, Packaging, Signing & Notarization Guide

## 1. Supported Architectures & Artifacts

StorageCleaner is packaged as a Universal 2 macOS application supporting:
- **Apple Silicon:** `arm64` (M1, M2, M3, M4, etc.)
- **Intel:** `x86_64`

### Generated Distribution Artifacts:
- **Application Bundle:** `dist/StorageCleaner.app`
- **Disk Image:** `dist/StorageCleaner.dmg`

---

## 2. Automated Build & Packaging Pipeline

To compile, link universal binaries, assemble the `.app` bundle, sign with ad-hoc signature, and generate the `.dmg`:

```bash
chmod +x scripts/build_release.sh
./scripts/build_release.sh
```

---

## 3. Four-Tier Release Verification Levels

### Level 1: Development Build
- Built via `swift build` or `swift run StorageCleaner`.
- Unpackaged binary running within the workspace directory.

### Level 2: Locally Installable Package (Current Status in Workspace)
- Merged into Universal Mach-O 2 binary (`arm64` + `x86_64`) via `lipo`.
- Encapsulated in macOS bundle structure:
  - `StorageCleaner.app/Contents/MacOS/StorageCleaner`
  - `StorageCleaner.app/Contents/Info.plist`
- Ad-hoc signed (`codesign --force --deep --sign - dist/StorageCleaner.app`).
- Packaged in verified disk image (`dist/StorageCleaner.dmg`).
- Runs directly on local developer machines.

### Level 3: Signed Distribution Build (Requires Apple Developer ID)
When legitimate Apple Developer ID Application certificates are present in Keychain:

```bash
export SIGN_IDENTITY="Developer ID Application: Your Name (TEAM_ID)"
./scripts/build_release.sh
```

### Level 4: Notarized Release for Public Distribution
To notarize the DMG with Apple's Notary Service:

```bash
# 1. Store notary credentials in keychain (one-time setup)
xcrun notarytool store-credentials "AC_PASSWORD" \
  --apple-id "developer@example.com" \
  --team-id "TEAM_ID" \
  --password "app-specific-password"

# 2. Submit DMG to Apple Notary Service
xcrun notarytool submit dist/StorageCleaner.dmg \
  --keychain-profile "AC_PASSWORD" \
  --wait

# 3. Staple the notarization ticket to the DMG
xcrun stapler staple dist/StorageCleaner.dmg

# 4. Validate stapling
spctl -a -t open --context context:primary-signature -v dist/StorageCleaner.dmg
```

*Note: In the current development environment without Apple Developer credentials, steps 1 and 2 (development and locally installable packages) are 100% completed and cryptographically verified on disk. Steps 3 and 4 require an active Apple Developer Program membership.*
