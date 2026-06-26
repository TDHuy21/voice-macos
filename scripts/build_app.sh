#!/bin/bash
set -e

# Configuration
APP_NAME="SoundsSource"
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONFIGURATION="release"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -d|--debug) CONFIGURATION="debug"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
done

echo "=== Building SoundsSource ($CONFIGURATION) ==="
swift build -c "$CONFIGURATION"

# Create bundle directory structure
echo "=== Assembling App Bundle ==="
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary and plist
BINARY_PATH=".build/$CONFIGURATION/$APP_NAME"
if [ ! -f "$BINARY_PATH" ]; then
    # SPM sometimes puts executables in apple/Products
    BINARY_PATH=$(find .build -name "$APP_NAME" -type f | head -n 1)
fi

if [ -z "$BINARY_PATH" ] || [ ! -f "$BINARY_PATH" ]; then
    echo "Error: Compiled binary not found."
    exit 1
fi

cp "$BINARY_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"

# Sign bundle with entitlements. Prefer the stable self-signed identity so macOS
# remembers the audio-capture permission across rebuilds (ad-hoc changes identity
# every build → re-prompts). Run scripts/setup_signing_cert.sh once to create it.
SIGN_IDENTITY="SoundsSource Self-Signed"
if security find-identity -p codesigning | grep -q "$SIGN_IDENTITY"; then
    echo "=== Code Signing with stable identity: $SIGN_IDENTITY ==="
    codesign --force --sign "$SIGN_IDENTITY" --entitlements entitlements.plist "$APP_BUNDLE"
else
    echo "=== No stable identity — ad-hoc signing (run scripts/setup_signing_cert.sh to stop repeated permission prompts) ==="
    codesign --force --sign - --entitlements entitlements.plist "$APP_BUNDLE"
fi

echo "=== Build Complete: $APP_BUNDLE ==="
