#!/usr/bin/env bash
# Usage: ./scripts/release.sh <version>
# Example: ./scripts/release.sh 1.1.0
#
# Prerequisites:
#   gh auth login

set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "Usage: $0 <version>  (e.g. 1.1.0)" >&2
  exit 1
fi

TAG="v${VERSION}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAP_ROOT="$(cd "$REPO_ROOT/../homebrew-tap" 2>/dev/null && pwd)" || true
DMG_NAME="WhisperFly.dmg"
APP_NAME="WhisperFly.app"
BUILD_DIR="$REPO_ROOT/.build/release-stage"
ENTITLEMENTS="$REPO_ROOT/WhisperFly.entitlements"
SIGN_APP_SCRIPT="$REPO_ROOT/scripts/sign-app.sh"
DEVELOPER_IDENTITY="$(security find-identity -v -p codesigning | grep 'Developer ID Application' | head -1 | sed 's/.* "//; s/"$//' || true)"
APP_PATH="$REPO_ROOT/$APP_NAME"

echo "==> Building WhisperFly ${TAG}..."
./scripts/build-dev.sh --release

if [[ ! -d "$APP_PATH" ]]; then
  echo "ERROR: $APP_PATH not found after release build." >&2
  exit 1
fi

echo "==> Creating DMG..."
rm -rf "$BUILD_DIR" && mkdir -p "$BUILD_DIR"
cp -R "$APP_PATH" "$BUILD_DIR/"

echo "==> Signing release app with stable designated requirement..."
if [[ -n "$DEVELOPER_IDENTITY" ]]; then
  "$SIGN_APP_SCRIPT" \
    --app "$BUILD_DIR/$APP_NAME" \
    --entitlements "$ENTITLEMENTS" \
    --identity "$DEVELOPER_IDENTITY" \
    --require-distribution
else
  echo "WARN: No Developer ID Application certificate found. Falling back to Apple Development signing for this release."
  "$SIGN_APP_SCRIPT" \
    --app "$BUILD_DIR/$APP_NAME" \
    --entitlements "$ENTITLEMENTS"
fi

rm -f "$REPO_ROOT/$DMG_NAME"
hdiutil create \
  -volname "WhisperFly ${VERSION}" \
  -srcfolder "$BUILD_DIR" \
  -format UDZO \
  "$REPO_ROOT/$DMG_NAME"

if [[ -n "$DEVELOPER_IDENTITY" ]]; then
  echo "==> Signing DMG..."
  codesign --force --sign "$DEVELOPER_IDENTITY" "$REPO_ROOT/$DMG_NAME"
fi

SHA256=$(shasum -a 256 "$REPO_ROOT/$DMG_NAME" | awk '{print $1}')
echo "==> DMG SHA256: $SHA256"

echo "==> Tagging ${TAG} and pushing..."
git -C "$REPO_ROOT" tag "$TAG"
git -C "$REPO_ROOT" push origin "$TAG"

echo "==> Creating GitHub release..."
gh release create "$TAG" \
  "$REPO_ROOT/$DMG_NAME" \
  --repo dandysuper/WhisperFly \
  --title "WhisperFly ${TAG}" \
  --generate-notes

echo "==> Updating Homebrew tap cask..."
if [[ -d "$TAP_ROOT" ]]; then
  CASK_FILE="$TAP_ROOT/Casks/whisperfly.rb"
  sed -i '' "s/version \".*\"/version \"${VERSION}\"/" "$CASK_FILE"
  sed -i '' "s/sha256 \".*\"/sha256 \"${SHA256}\"/" "$CASK_FILE"
  git -C "$TAP_ROOT" add Casks/whisperfly.rb
  git -C "$TAP_ROOT" commit -m "chore: bump whisperfly to ${TAG}"
  git -C "$TAP_ROOT" push origin main
  echo "==> Tap updated."
else
  echo "WARN: Tap not found at $TAP_ROOT — update Casks/whisperfly.rb manually:"
  echo "  version \"${VERSION}\""
  echo "  sha256 \"${SHA256}\""
fi

echo "==> Done! Release ${TAG} is live."
