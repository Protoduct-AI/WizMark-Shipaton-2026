#!/usr/bin/env bash
# Shared helpers for the release scripts.
#
# Sourced, not executed. Everything here is written to be safe to run twice.

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────
PROJECT="WizMark.xcodeproj"
SCHEME="WizMark"
APP_ID="6784499093"
BUNDLE_ID="com.protoductai.wizmark"
SIGNING_KEYCHAIN="${WIZMARK_SIGNING_KEYCHAIN:-wizmark-signing.keychain}"
SIGNING_IDENTITY="Apple Distribution: PROTODUCTAI K.K. (UJTZMJ5D9Q)"
TESTFLIGHT_INTERNAL_GROUP="a144051e-dd74-4675-a2a1-e01bf372d0cc"
BUILD_DIR="${BUILD_DIR:-build/release}"

# One derived data directory for every xcodebuild in this repo. The archive used
# to fall back to the global one, so the SPM checkouts and module cache the
# preflight build had just warmed were invisible to it and every dependency —
# RevenueCat, ClerkKit, Sentry — was fetched and compiled a second time.
DERIVED_DATA="${DERIVED_DATA:-build/DerivedData}"

# Survives the rm -rf of BUILD_DIR on purpose: it records what the generated
# project was made from, so a rerun can tell whether regenerating is necessary.
PROJECT_HASH_FILE="${PROJECT_HASH_FILE:-build/.project-hash}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# ── Output ─────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
    C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
else
    C_RESET=''; C_BOLD=''; C_DIM=''; C_RED=''; C_GREEN=''; C_YELLOW=''
fi

step()  { printf '\n%s▸ %s%s\n' "$C_BOLD" "$*" "$C_RESET"; }
info()  { printf '  %s\n' "$*"; }
muted() { printf '  %s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }
ok()    { printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn()  { printf '  %s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
die()   { printf '\n  %s✗ %s%s\n\n' "$C_RED" "$*" "$C_RESET" >&2; exit 1; }

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "$1 が見つかりません。$2"
}

# ── Signing ────────────────────────────────────────────────────────────────
#
# Three separate problems have broken signing on this machine, all surfacing as
# the same useless "errSecInternalComponent". prepare_signing addresses each:
#
#   1. Other projects' keychains sit in the search list while locked. Every
#      keychain scan then blocks on a password prompt that never gets answered.
#   2. The signing keychain has no WWDR intermediate, so the certificate chain
#      cannot be built ("unable to build chain to self-signed root").
#   3. The default keychain points somewhere else, and codesign resolves the
#      identity against that rather than the one passed with --keychain.
#
# The original search list and default keychain are restored by restore_signing,
# which the caller wires to an EXIT trap.

SIGNING_PREPARED=0
ORIGINAL_KEYCHAIN_LIST=""
ORIGINAL_DEFAULT_KEYCHAIN=""

prepare_signing() {
    [[ -n "${WIZMARK_KEYCHAIN_PASSWORD:-}" ]] \
        || die "署名には WIZMARK_KEYCHAIN_PASSWORD の設定が必要です"
    local password="$WIZMARK_KEYCHAIN_PASSWORD"

    step "署名環境を準備"

    ORIGINAL_KEYCHAIN_LIST="$(security list-keychains -d user | tr -d ' "')"
    ORIGINAL_DEFAULT_KEYCHAIN="$(security default-keychain -d user | tr -d ' "')"
    SIGNING_PREPARED=1

    security list-keychains -d user -s "$SIGNING_KEYCHAIN" login.keychain
    security unlock-keychain -p "$password" "$SIGNING_KEYCHAIN" \
        || die "$SIGNING_KEYCHAIN を解錠できません。WIZMARK_KEYCHAIN_PASSWORD を確認してください"
    security set-keychain-settings -t 36000 -u "$SIGNING_KEYCHAIN"
    security default-keychain -d user -s "$SIGNING_KEYCHAIN"
    ok "キーチェーンを解錠し、既定に設定"

    ensure_wwdr_certificates
    verify_signing_identity
}

# Import the Apple intermediates into the signing keychain when missing, so the
# chain resolves without depending on whatever else is in the search list.
ensure_wwdr_certificates() {
    local count
    count="$(security find-certificate -a -c "Worldwide Developer Relations" \
        "$HOME/Library/Keychains/${SIGNING_KEYCHAIN}-db" 2>/dev/null \
        | grep -c "keychain:" || true)"

    if [[ "${count:-0}" -gt 0 ]]; then
        ok "WWDR 中間証明書あり (${count} 件)"
        return
    fi

    warn "WWDR 中間証明書がないため取り込みます"
    local tmp; tmp="$(mktemp -d)"
    security find-certificate -a -c "Worldwide Developer Relations" -p \
        > "$tmp/wwdr.pem" 2>/dev/null || true
    security find-certificate -a -c "Apple Root CA" -p \
        /System/Library/Keychains/SystemRootCertificates.keychain \
        > "$tmp/root.pem" 2>/dev/null || true

    for pem in "$tmp/wwdr.pem" "$tmp/root.pem"; do
        [[ -s "$pem" ]] || continue
        security import "$pem" -k "$HOME/Library/Keychains/${SIGNING_KEYCHAIN}-db" \
            -T /usr/bin/codesign -T /usr/bin/security >/dev/null 2>&1 || true
    done
    rm -rf "$tmp"
    ok "WWDR / Apple Root を取り込みました"
}

verify_signing_identity() {
    security find-identity -v -p codesigning "$SIGNING_KEYCHAIN" \
        | grep -qF "$SIGNING_IDENTITY" \
        || die "署名 ID が見つかりません: $SIGNING_IDENTITY"
    ok "署名 ID を確認"
}

restore_signing() {
    [[ "$SIGNING_PREPARED" == "1" ]] || return 0
    if [[ -n "$ORIGINAL_KEYCHAIN_LIST" ]]; then
        security list-keychains -d user -s $ORIGINAL_KEYCHAIN_LIST >/dev/null 2>&1 || true
    fi
    if [[ -n "$ORIGINAL_DEFAULT_KEYCHAIN" ]]; then
        security default-keychain -d user -s "$ORIGINAL_DEFAULT_KEYCHAIN" >/dev/null 2>&1 || true
    fi
    SIGNING_PREPARED=0
}

# Provisioning profiles go stale silently: the profile keeps working for older
# certificates and simply stops matching the current one, which xcodebuild only
# reports once the archive is already underway.
verify_profile_matches_certificate() {
    local wanted_profile="$1"
    local fingerprint
    fingerprint="$(security find-certificate -c "Apple Distribution: PROTODUCTAI" -p \
        "$HOME/Library/Keychains/${SIGNING_KEYCHAIN}-db" 2>/dev/null \
        | openssl x509 -noout -fingerprint -sha1 2>/dev/null \
        | sed 's/.*=//; s/://g')"
    if [[ -z "$fingerprint" ]]; then
        warn "証明書の指紋を取得できずプロファイル照合を省略"
        return 0
    fi

    local dir="$HOME/Library/MobileDevice/Provisioning Profiles"
    local tmp; tmp="$(mktemp -d)"
    local matched=0

    for profile in "$dir"/*.mobileprovision; do
        [[ -f "$profile" ]] || continue
        security cms -D -i "$profile" 2>/dev/null \
            | plutil -convert xml1 -o "$tmp/p.plist" - 2>/dev/null || continue
        local name
        name="$(plutil -extract Name raw "$tmp/p.plist" 2>/dev/null || true)"
        [[ "$name" == "$wanted_profile" ]] || continue

        local n; n="$(plutil -extract DeveloperCertificates raw "$tmp/p.plist" 2>/dev/null || echo 0)"
        for ((i = 0; i < n; i++)); do
            plutil -extract "DeveloperCertificates.$i" raw -o "$tmp/c.b64" "$tmp/p.plist" 2>/dev/null || continue
            base64 -d < "$tmp/c.b64" > "$tmp/c.der" 2>/dev/null || continue
            local fp
            fp="$(openssl x509 -inform DER -in "$tmp/c.der" -noout -fingerprint -sha1 2>/dev/null \
                | sed 's/.*=//; s/://g')"
            [[ "$fp" == "$fingerprint" ]] && matched=1
        done
    done
    rm -rf "$tmp"

    [[ "$matched" == "1" ]] \
        || die "プロファイル \"$wanted_profile\" は現在の証明書を含みません。Apple Developer で再生成してください"
    ok "プロファイル \"$wanted_profile\" と証明書が一致"
}

# ── Project generation ─────────────────────────────────────────────────────
#
# XcodeGen rewrites WizMark.xcodeproj wholesale. Xcode treats the new file as a
# changed project and rebuilds everything it references, including every SPM
# dependency, which is most of the 37 minutes an archive was taking. Regenerate
# only when the inputs actually changed.
#
# The fingerprint covers project.yml *and* the layout of the source tree: the
# targets take whole directories, so a new file changes no YAML but still has to
# reach the project. File contents are deliberately not hashed — editing a
# Swift file needs a recompile, not a regenerated project.
project_fingerprint() {
    {
        shasum project.yml
        find Sources -type f -print 2>/dev/null | LC_ALL=C sort
    } | shasum | cut -d' ' -f1
}

ensure_project_generated() {
    local current previous=""
    current="$(project_fingerprint)"
    [[ -f "$PROJECT_HASH_FILE" ]] && previous="$(cat "$PROJECT_HASH_FILE")"

    if [[ -d "$PROJECT" && -n "$previous" && "$current" == "$previous" ]]; then
        ok "$PROJECT は最新（再生成を省略）"
        return 0
    fi

    xcodegen generate >/dev/null
    mkdir -p "$(dirname "$PROJECT_HASH_FILE")"
    printf '%s\n' "$current" > "$PROJECT_HASH_FILE"
    ok "$PROJECT を生成"
}

# ── xcodebuild ─────────────────────────────────────────────────────────────
#
# xcodebuild runs with `|| true` so the log can be read either way, and the old
# check read it for exactly two outcomes: ARCHIVE SUCCEEDED, or `error:` lines.
# An interrupted run is neither. The 2026-08-23 archive ran 37 minutes, died
# mid-RevenueCat, and left 2875 lines with no SUCCEEDED, no FAILED and no
# `error:` — so the script printed nothing at all and exited quietly.
#
# It was not even silent: the last line read "** BUILD INTERRUPTED **". Nothing
# was looking for it.
assert_build_marker() {
    local log="$1" success="$2" failure="$3" label="$4"
    local error_pattern="${5:-error:}"

    if grep -qF "$success" "$log"; then
        ok "$success"
        return 0
    fi

    if grep -qF "$failure" "$log"; then
        grep -E "$error_pattern" "$log" | head -20
        die "${label}に失敗しました ($log)"
    fi

    # xcodebuild does say so when it is killed — it prints "BUILD INTERRUPTED"
    # for every action, archive included. Nothing looked for it, which is why
    # the 2026-08-23 run ended in silence after 37 minutes.
    if grep -qF '** BUILD INTERRUPTED **' "$log"; then
        show_log_tail "$log"
        die "${label}が中断されました（** BUILD INTERRUPTED **）。ログ: $log"
    fi

    warn "ログに完了マーカー（${success} / ${failure}）がありません。中断された可能性があります"
    show_log_tail "$log"
    die "${label}が完了しませんでした（中断の可能性）。ログ: $log"
}

# Compile lines name every file in the module and run to tens of kilobytes, so
# the tail is truncated to stay readable in a terminal.
show_log_tail() {
    info "ログ末尾:"
    tail -20 "$1" | cut -c1-160 | sed 's/^/    /'
}

# ── Simulator ──────────────────────────────────────────────────────────────
#
# Names like "iPhone 16 Pro" are ambiguous once several runtimes are installed,
# and xcodebuild then reports only "Unable to find a device matching the
# provided destination specifier". Resolve to a UDID instead.
resolve_simulator() {
    if [[ -n "${WIZMARK_SIMULATOR:-}" ]]; then
        echo "$WIZMARK_SIMULATOR"
        return
    fi
    local udid
    udid="$(xcrun simctl list devices available -j 2>/dev/null | python3 -c '
import json, sys
data = json.load(sys.stdin)["devices"]
best = None
for runtime, devices in data.items():
    if "iOS" not in runtime:
        continue
    for d in devices:
        if not d.get("isAvailable"):
            continue
        name = d.get("name", "")
        if not name.startswith("iPhone"):
            continue
        # Prefer a booted device so repeated runs reuse the same simulator.
        rank = (d.get("state") == "Booted", "Pro" in name)
        if best is None or rank > best[0]:
            best = (rank, d["udid"])
print(best[1] if best else "")
')"
    [[ -n "$udid" ]] || die "利用可能な iPhone シミュレータが見つかりません"
    echo "id=$udid"
}

# ── App Store Connect ──────────────────────────────────────────────────────
latest_build_number() {
    asc builds list --app "$APP_ID" 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print(0); raise SystemExit
best = 0
for b in d.get("data", []):
    try:
        best = max(best, int(b["attributes"].get("version") or 0))
    except (TypeError, ValueError):
        pass
print(best)
'
}

# Prints "<state> <id>" for the given build number, or nothing when absent.
build_state() {
    asc builds list --app "$APP_ID" 2>/dev/null | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    raise SystemExit
for b in d.get('data', []):
    if b['attributes'].get('version') == '$1':
        print(b['attributes'].get('processingState', ''), b['id'])
        break
"
}

# The newest version App Store Connect already knows about.
#
# Metadata for a new version is copied from this, not from project.yml — by the
# time a release runs, project.yml already holds the version being created, and
# asking to copy from a version that does not exist yet fails.
latest_store_version() {
    asc versions list --app "$APP_ID" 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    raise SystemExit
best = None
for v in d.get("data", []):
    raw = v["attributes"].get("versionString")
    if not raw:
        continue
    try:
        parts = tuple(int(p) for p in raw.split("."))
    except ValueError:
        continue
    if best is None or parts > best[0]:
        best = (parts, raw)
print(best[1] if best else "")
'
}

current_marketing_version() {
    grep -m1 'MARKETING_VERSION:' project.yml | sed 's/.*"\(.*\)".*/\1/'
}

current_build_number() {
    grep -m1 'CURRENT_PROJECT_VERSION:' project.yml | sed 's/.*"\(.*\)".*/\1/'
}

set_build_number() {
    /usr/bin/sed -i '' "s/CURRENT_PROJECT_VERSION: \"[0-9]*\"/CURRENT_PROJECT_VERSION: \"$1\"/g" project.yml
}

set_marketing_version() {
    /usr/bin/sed -i '' "s/MARKETING_VERSION: \"[^\"]*\"/MARKETING_VERSION: \"$1\"/g" project.yml
}
