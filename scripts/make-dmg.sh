#!/usr/bin/env bash
# scripts/make-dmg.sh
#
# Packs WhisperFly.app into a drag-to-Applications disk image with the
# WhisperFly background, icon layout and volume icon.
#
# Usage:
#   ./scripts/make-dmg.sh [--app PATH] [--version X.Y.Z] [--output PATH] [--sign IDENTITY]
#
# Defaults: ./WhisperFly.app, the VERSION file, ./WhisperFly.dmg, no signing.
#
# The layout is written by dmgbuild (MIT, https://github.com/dmgbuild/dmgbuild),
# which creates Finder's .DS_Store directly — no Finder scripting, so it works
# headless and never asks for Automation access. It is installed into a private
# virtualenv under ~/Library/Caches the first time this runs.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$REPO_ROOT/WhisperFly.app"
VERSION="$(tr -d '[:space:]' < "$REPO_ROOT/VERSION" 2>/dev/null || echo 0.0.0)"
OUTPUT="$REPO_ROOT/WhisperFly.dmg"
SIGN_IDENTITY=""
DMGBUILD_VERSION="1.6.7"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app)     APP_PATH="$2"; shift 2 ;;
        --version) VERSION="$2"; shift 2 ;;
        --output)  OUTPUT="$2"; shift 2 ;;
        --sign)    SIGN_IDENTITY="$2"; shift 2 ;;
        -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
        *) echo "ERROR: unknown argument: $1" >&2; exit 1 ;;
    esac
done

[[ -d "$APP_PATH" ]] || { echo "ERROR: app not found: $APP_PATH" >&2; exit 1; }

WORK="$(mktemp -d -t whisperfly-dmg)"
trap 'rm -rf "$WORK"' EXIT

# --- dmgbuild -------------------------------------------------------------------

VENV="$HOME/Library/Caches/WhisperFly/dmgbuild-$DMGBUILD_VERSION"
if [[ ! -x "$VENV/bin/dmgbuild" ]]; then
    echo "==> Installing dmgbuild $DMGBUILD_VERSION into $VENV..."
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install --quiet --disable-pip-version-check "dmgbuild==$DMGBUILD_VERSION"
fi

# --- Background -----------------------------------------------------------------

echo "==> Rendering background (version $VERSION)..."
swift "$REPO_ROOT/scripts/dmg/render-background.swift" "$WORK" "$VERSION" | grep -v '^wrote ' || true
[[ -f "$WORK/background@2x.png" ]] || { echo "ERROR: background rendering failed" >&2; exit 1; }
# One TIFF holding both resolutions, so Retina displays get the 2x artwork.
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" -out "$WORK/background.tiff" >/dev/null

ICON="$APP_PATH/Contents/Resources/AppIcon.icns"

# --- Image ----------------------------------------------------------------------

echo "==> Building $(basename "$OUTPUT")..."
rm -f "$OUTPUT"
"$VENV/bin/dmgbuild" \
    -s "$REPO_ROOT/scripts/dmg/settings.py" \
    -D app="$APP_PATH" \
    -D background="$WORK/background.tiff" \
    -D icon="$ICON" \
    "WhisperFly $VERSION" \
    "$OUTPUT"

if [[ -n "$SIGN_IDENTITY" ]]; then
    echo "==> Signing disk image..."
    codesign --force --sign "$SIGN_IDENTITY" "$OUTPUT"
fi

hdiutil verify -quiet "$OUTPUT"
echo "==> $(basename "$OUTPUT"): $(du -h "$OUTPUT" | cut -f1) · WhisperFly $VERSION"
