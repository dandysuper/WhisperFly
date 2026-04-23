#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  ./scripts/sign-app.sh --app /path/to/App.app --entitlements /path/to/App.entitlements [--identity "Developer ID Application: ..."] [--require-distribution]
  ./scripts/sign-app.sh --print-designated-requirement --bundle-id com.example.App --team-id TEAMID

Environment:
  WHISPERFLY_CODESIGN_IDENTITY  Override the signing identity.
  WHISPERFLY_TEAM_ID            Override the Team ID used in the designated requirement.
EOF
}

APP_BUNDLE=""
ENTITLEMENTS=""
IDENTITY="${WHISPERFLY_CODESIGN_IDENTITY:-}"
TEAM_ID="${WHISPERFLY_TEAM_ID:-}"
BUNDLE_ID=""
PRINT_REQUIREMENT=0
REQUIRE_DISTRIBUTION=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app)
            APP_BUNDLE="$2"
            shift 2
            ;;
        --entitlements)
            ENTITLEMENTS="$2"
            shift 2
            ;;
        --identity)
            IDENTITY="$2"
            shift 2
            ;;
        --bundle-id)
            BUNDLE_ID="$2"
            shift 2
            ;;
        --team-id)
            TEAM_ID="$2"
            shift 2
            ;;
        --print-designated-requirement)
            PRINT_REQUIREMENT=1
            shift
            ;;
        --require-distribution)
            REQUIRE_DISTRIBUTION=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

detect_identity() {
    local match="$1"
    security find-identity -v -p codesigning \
        | grep "$match" \
        | head -1 \
        | sed 's/.* "//; s/"$//' \
        || true
}

extract_team_id_from_identity() {
    local identity="$1"
    local subject
    subject="$(security find-certificate -c "$identity" -p 2>/dev/null \
        | openssl x509 -noout -subject 2>/dev/null || true)"

    if [[ -n "$subject" ]]; then
        echo "$subject" | sed -n 's/.*OU=\([^,\/]*\).*/\1/p' | head -1
        return
    fi

    echo "$identity" | sed -n 's/.*(\([A-Z0-9]\{10\}\)).*/\1/p'
}

designated_requirement() {
    local bundle_id="$1"
    local team_id="$2"
    cat <<EOF
designated => anchor apple generic and identifier "$bundle_id" and certificate leaf[subject.OU] = $team_id
EOF
}

if [[ $PRINT_REQUIREMENT -eq 1 ]]; then
    if [[ -z "$BUNDLE_ID" || -z "$TEAM_ID" ]]; then
        echo "ERROR: --print-designated-requirement requires --bundle-id and --team-id" >&2
        exit 1
    fi
    designated_requirement "$BUNDLE_ID" "$TEAM_ID"
    exit 0
fi

if [[ -z "$APP_BUNDLE" || -z "$ENTITLEMENTS" ]]; then
    echo "ERROR: --app and --entitlements are required" >&2
    usage >&2
    exit 1
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "ERROR: app bundle not found: $APP_BUNDLE" >&2
    exit 1
fi

if [[ ! -f "$ENTITLEMENTS" ]]; then
    echo "ERROR: entitlements file not found: $ENTITLEMENTS" >&2
    exit 1
fi

if [[ -z "$BUNDLE_ID" ]]; then
    BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw -o - "$APP_BUNDLE/Contents/Info.plist")"
fi

if [[ -z "$IDENTITY" ]]; then
    if [[ $REQUIRE_DISTRIBUTION -eq 1 ]]; then
        IDENTITY="$(detect_identity "Developer ID Application")"
    else
        IDENTITY="$(detect_identity "Developer ID Application")"
        if [[ -z "$IDENTITY" ]]; then
            IDENTITY="$(detect_identity "Apple Development")"
        fi
    fi
fi

if [[ -z "$IDENTITY" ]]; then
    if [[ $REQUIRE_DISTRIBUTION -eq 1 ]]; then
        echo "ERROR: No Developer ID Application certificate found. Install one or pass --identity." >&2
    else
        echo "ERROR: No signing identity found. Install an Apple Development or Developer ID Application certificate." >&2
    fi
    exit 1
fi

if [[ -z "$TEAM_ID" ]]; then
    TEAM_ID="$(extract_team_id_from_identity "$IDENTITY")"
fi

if [[ -z "$TEAM_ID" ]]; then
    echo "ERROR: Unable to determine Team ID for signing identity: $IDENTITY" >&2
    exit 1
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT
REQ_FILE="$TMPDIR/designated.req"
designated_requirement "$BUNDLE_ID" "$TEAM_ID" > "$REQ_FILE"

echo "==> Signing $APP_BUNDLE"
echo "    Identity: $IDENTITY"
echo "    Team ID:  $TEAM_ID"
echo "    Bundle ID: $BUNDLE_ID"

codesign \
    --force \
    --sign "$IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    --options runtime \
    --requirements "$REQ_FILE" \
    "$APP_BUNDLE"

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "==> Designated requirement"
codesign -d -r- "$APP_BUNDLE" 2>&1 | sed -n 's/^designated => /designated => /p'

if [[ "$IDENTITY" == Developer\ ID\ Application:* ]]; then
    echo "==> Gatekeeper assessment"
    spctl -a -t exec -vv "$APP_BUNDLE"
fi
