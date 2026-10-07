#!/usr/bin/env bash
# scripts/build-app.sh
#
# The canonical packager: builds the Swift package, assembles WhisperFly.app
# from scratch, stamps the build metadata that BuildInfo reads at runtime, and
# signs the bundle with the stable designated requirement that keeps TCC
# permission grants alive across updates.
#
# Usage:
#   ./scripts/build-app.sh                       # release build of the host arch
#   ./scripts/build-app.sh --config debug        # debug build
#   ./scripts/build-app.sh --universal           # universal (arm64 + x86_64) binary
#   ./scripts/build-app.sh --version 2.1.0       # override the marketing version
#   ./scripts/build-app.sh --no-sign             # skip codesigning entirely
#
# This is also what the in-app updater invokes when rebuilding a source checkout
# (UpdateInstaller.rebuildFromSource), so it must work in a fresh clone with
# nothing but Xcode Command Line Tools installed.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="$REPO_ROOT/WhisperFly.app"
ENTITLEMENTS="$REPO_ROOT/WhisperFly.entitlements"
SIGN_APP_SCRIPT="$REPO_ROOT/scripts/sign-app.sh"
INFO_PLIST_TEMPLATE="$REPO_ROOT/scripts/Info.plist"
ICON_SOURCE="$REPO_ROOT/Sources/WhisperFly/Resources/AppIcon.icns"

BUILD_CONFIG="release"
MARKETING_VERSION="${WHISPERFLY_VERSION:-}"
UNIVERSAL=0
DO_SIGN=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)     BUILD_CONFIG="$2"; shift 2 ;;
        --version)    MARKETING_VERSION="$2"; shift 2 ;;
        --universal)  UNIVERSAL=1; shift ;;
        --no-sign)    DO_SIGN=0; shift ;;
        -h|--help)    sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "ERROR: unknown argument: $1" >&2; exit 1 ;;
    esac
done

cd "$REPO_ROOT"

# --- Build -------------------------------------------------------------------

SWIFT_FLAGS=(-c "$BUILD_CONFIG")
if [[ $UNIVERSAL -eq 1 ]]; then
    SWIFT_FLAGS+=(--arch arm64 --arch x86_64)
fi

echo "==> Building WhisperFly (${BUILD_CONFIG}$([[ $UNIVERSAL -eq 1 ]] && echo ', universal'))..."
swift build "${SWIFT_FLAGS[@]}"

BIN_DIR="$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path)"
BUILT_BINARY="$BIN_DIR/WhisperFly"
BUILT_RESOURCES="$BIN_DIR/WhisperFly_WhisperFly.bundle"

if [[ ! -f "$BUILT_BINARY" ]]; then
    echo "ERROR: built binary not found at: $BUILT_BINARY" >&2
    exit 1
fi

# --- Stamp values ------------------------------------------------------------

if [[ -z "$MARKETING_VERSION" ]]; then
    # Latest tag without its `v` prefix; falls back to 0.0.0 before the first tag.
    MARKETING_VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
    MARKETING_VERSION="${MARKETING_VERSION:-0.0.0}"
fi
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
COMMIT_SHA="$(git rev-parse HEAD 2>/dev/null || echo "")"
COMMIT_DATE="$(git log -1 --format=%cI 2>/dev/null || echo "")"
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# `owner/name` from the origin remote, e.g. git@github.com:dandysuper/WhisperFly.git
REPOSITORY="$(git remote get-url origin 2>/dev/null | sed -E 's#.*[:/]([^/]+/[^/]+)(\.git)?$#\1#; s#\.git$##' || true)"
REPOSITORY="${REPOSITORY:-dandysuper/WhisperFly}"
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo master)"
BRANCH="${BRANCH:-master}"

# --- Assemble the bundle ------------------------------------------------------

echo "==> Assembling $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$BUILT_BINARY" "$APP_BUNDLE/Contents/MacOS/WhisperFly"
chmod +x "$APP_BUNDLE/Contents/MacOS/WhisperFly"
cp "$INFO_PLIST_TEMPLATE" "$APP_BUNDLE/Contents/Info.plist"
if [[ -f "$ICON_SOURCE" ]]; then
    cp "$ICON_SOURCE" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi
if [[ -d "$BUILT_RESOURCES" ]]; then
    cp -R "$BUILT_RESOURCES" "$APP_BUNDLE/Contents/Resources/"
fi

PLIST="$APP_BUNDLE/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$MARKETING_VERSION" "$PLIST"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$PLIST"
plutil -replace WhisperFlyCommitSHA  -string "$COMMIT_SHA"  "$PLIST"
plutil -replace WhisperFlyCommitDate -string "$COMMIT_DATE" "$PLIST"
plutil -replace WhisperFlyBuildDate  -string "$BUILD_DATE"  "$PLIST"
plutil -replace WhisperFlyRepository -string "$REPOSITORY"  "$PLIST"
plutil -replace WhisperFlyBranch     -string "$BRANCH"      "$PLIST"

# --- Sign ---------------------------------------------------------------------

if [[ $DO_SIGN -eq 1 ]]; then
    if security find-identity -v -p codesigning 2>/dev/null | grep -q '"'; then
        echo "==> Signing with the stable designated requirement..."
        "$SIGN_APP_SCRIPT" --app "$APP_BUNDLE" --entitlements "$ENTITLEMENTS" \
            $([[ "${WHISPERFLY_REQUIRE_DISTRIBUTION:-}" = "1" ]] && echo --require-distribution)
    else
        # Ad-hoc keeps a build runnable, but macOS keys permission grants to the
        # exact binary, so every rebuild resets Microphone/Screen Recording/
        # Accessibility until the app is signed with a real certificate.
        echo "WARN: no signing identity found — falling back to ad-hoc." >&2
        echo "WARN: permissions will reset on the next rebuild." >&2
        codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"
    fi
fi

echo ""
echo "Build complete!"
echo "  App:      $APP_BUNDLE"
echo "  Version:  $MARKETING_VERSION ($BUILD_NUMBER) · ${COMMIT_SHA:0:7}"
echo "  Repo:     $REPOSITORY@$BRANCH"
echo ""
echo "To launch:"
echo "  open $APP_BUNDLE"
