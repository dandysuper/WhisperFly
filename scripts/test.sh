#!/usr/bin/env bash
# scripts/test.sh
#
# Runs the test suite. On a Command Line Tools–only toolchain the Swift Testing
# macro plugin lives in a subdirectory (`plugins/testing/`) that the build
# system only sometimes picks up, so the path is handed to the driver
# explicitly. With a full Xcode toolchain a plain `swift test` works too; this
# script works in both.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

TOOLCHAIN_DIR="$(dirname "$(dirname "$(xcrun --find swift)")")"   # .../usr/bin
CLT_PLUGIN_DIR="$TOOLCHAIN_DIR/swift/host/plugins/testing"

PLUGIN_FLAGS=()
if [[ -d "$CLT_PLUGIN_DIR" ]]; then
    SERVER="$(dirname "$(dirname "$(xcrun --find swift)")")/bin/swift-plugin-server"
    [[ -x "$SERVER" ]] || SERVER="/Library/Developer/CommandLineTools/usr/bin/swift-plugin-server"
    PLUGIN_FLAGS=(
        -Xswiftc -external-plugin-path -Xswiftc "$CLT_PLUGIN_DIR#$SERVER"
        -Xswiftc -external-plugin-path -Xswiftc "$(dirname "$CLT_PLUGIN_DIR")#$SERVER"
    )
fi

# `${PLUGIN_FLAGS[@]+"${PLUGIN_FLAGS[@]}"}` expands to nothing on bash 3.2
# (the macOS default) when the array is empty, without tripping `set -u`.

# The CLT build plan intermittently drops the plugin path when recompiling an
# already-built test module; a retry on the build step covers it.
for attempt in 1 2 3; do
    if swift build --build-tests ${PLUGIN_FLAGS[@]+"${PLUGIN_FLAGS[@]}"}; then
        break
    fi
    [[ $attempt -eq 3 ]] && exit 1
    echo "==> Build failed (attempt $attempt), retrying..."
done

swift test --skip-build
