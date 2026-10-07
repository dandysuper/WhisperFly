#!/usr/bin/env bash
# scripts/build-dev.sh
#
# Builds WhisperFly (debug by default), copies the binary into the .app bundle,
# and re-signs it with the required entitlements so that Hardened Runtime permits
# microphone access and AppleScript/CGEvent keyboard injection.
#
# Usage:
#   ./scripts/build-dev.sh              # debug build
#   ./scripts/build-dev.sh --release    # release build
#
# Prerequisites:
#   - Xcode Command Line Tools
#   - A valid "Apple Development" signing identity in your Keychain
#     (run: security find-identity -v -p codesigning)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="$REPO_ROOT/WhisperFly.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/WhisperFly"
ENTITLEMENTS="$REPO_ROOT/WhisperFly.entitlements"
SIGN_APP_SCRIPT="$REPO_ROOT/scripts/sign-app.sh"

# Build configuration
BUILD_CONFIG="debug"
SWIFT_BUILD_FLAGS=""
if [ "${1:-}" = "--release" ]; then
    BUILD_CONFIG="release"
    SWIFT_BUILD_FLAGS="-c release"
fi

echo "==> Building WhisperFly (${BUILD_CONFIG}, $(uname -m))..."
cd "$REPO_ROOT"
swift build $SWIFT_BUILD_FLAGS

# Resolve the binary through SwiftPM itself rather than guessing the scratch
# layout — it moves between `.build/debug` and `.build/out/Products/Debug`
# depending on toolchain and scratch-path configuration.
BIN_DIR="$(swift build $SWIFT_BUILD_FLAGS --show-bin-path)"
BUILT_BINARY="$BIN_DIR/WhisperFly"
BUILT_RESOURCES="$BIN_DIR/WhisperFly_WhisperFly.bundle"

if [ ! -f "$BUILT_BINARY" ]; then
    echo "ERROR: built binary not found at: $BUILT_BINARY" >&2
    exit 1
fi

# Copy binary into app bundle
echo "==> Copying binary into $APP_BUNDLE..."
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
if [[ ! -f "$APP_BUNDLE/Contents/Info.plist" ]]; then
    # Fresh clone: the committed bundle was removed from the repo, so start
    # from the template the release build uses.
    cp "$REPO_ROOT/scripts/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
fi
if [[ ! -f "$APP_BUNDLE/Contents/Resources/AppIcon.icns" && -f "$REPO_ROOT/Sources/WhisperFly/Resources/AppIcon.icns" ]]; then
    cp "$REPO_ROOT/Sources/WhisperFly/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi
cp "$BUILT_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

# Refresh the SwiftPM resource bundle so dev builds carry current localizations.
if [ -d "$BUILT_RESOURCES" ]; then
    echo "==> Refreshing resource bundle..."
    rm -rf "$APP_BUNDLE/Contents/Resources/WhisperFly_WhisperFly.bundle"
    cp -R "$BUILT_RESOURCES" "$APP_BUNDLE/Contents/Resources/"
fi

# Stamp the commit metadata BuildInfo reads, so the updater can compare a dev
# build against the branch head instead of reporting an unstamped revision.
echo "==> Stamping build metadata..."
PLIST="$APP_BUNDLE/Contents/Info.plist"
COMMIT_SHA="$(git rev-parse HEAD 2>/dev/null || echo "")"
COMMIT_DATE="$(git log -1 --format=%cI 2>/dev/null || echo "")"
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo master)"
plutil -replace WhisperFlyCommitSHA  -string "$COMMIT_SHA"  "$PLIST"
plutil -replace WhisperFlyCommitDate -string "$COMMIT_DATE" "$PLIST"
plutil -replace WhisperFlyBuildDate  -string "$BUILD_DATE"  "$PLIST"
plutil -replace WhisperFlyBranch     -string "$BRANCH"      "$PLIST"

echo "==> Re-signing app bundle with stable designated requirement..."
"$SIGN_APP_SCRIPT" \
    --app "$APP_BUNDLE" \
    --entitlements "$ENTITLEMENTS"

echo ""
echo "Build complete!"
echo "  App:    $APP_BUNDLE"
echo "  Binary: $APP_BINARY"
echo ""
echo "To launch:"
echo "  open $APP_BUNDLE"
echo ""
echo "After first launch, grant permissions in:"
echo "  System Settings -> Privacy & Security -> Microphone       (for mic recording)"
echo "  System Settings -> Privacy & Security -> Screen Recording (for system audio)"
echo "  System Settings -> Privacy & Security -> Accessibility    (for text injection)"
