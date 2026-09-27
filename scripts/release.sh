#!/usr/bin/env bash
# Archive, upload, and distribute WizMark from one command.
#
#   scripts/release.sh testflight              次のビルド番号で TestFlight へ
#   scripts/release.sh testflight --build 21   ビルド番号を指定
#   scripts/release.sh submit --version 1.0.2  審査へ提出（バージョンも作る）
#   scripts/release.sh status                  現在の状態を表示
#
# Options:
#   --skip-preflight   ビルド・テスト・検査を省く
#   --dry-run          アップロードと提出を行わず、直前で止める
#
# The keychain search list and default keychain are restored on exit, including
# when the script fails partway.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

COMMAND="${1:-status}"; shift || true

BUILD_NUMBER=""
MARKETING_VERSION=""
SKIP_PREFLIGHT=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --build)          BUILD_NUMBER="$2"; shift 2 ;;
        --version)        MARKETING_VERSION="$2"; shift 2 ;;
        --skip-preflight) SKIP_PREFLIGHT=1; shift ;;
        --dry-run)        DRY_RUN=1; shift ;;
        *) die "不明なオプション: $1" ;;
    esac
done

require_cmd asc "brew install rorkai/tap/asc"
require_cmd xcodegen "brew install xcodegen"

# ── status ─────────────────────────────────────────────────────────────────
show_status() {
    step "ローカル"
    info "バージョン : $(current_marketing_version) (build $(current_build_number))"
    info "ブランチ   : $(git branch --show-current)"
    local dirty; dirty="$(git status --porcelain | wc -l | tr -d ' ')"
    [[ "$dirty" == "0" ]] && ok "作業ツリーはクリーン" || warn "未コミットの変更が $dirty 件"

    step "App Store Connect"
    asc builds list --app "$APP_ID" 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin)
for b in d.get("data", [])[:5]:
    a = b["attributes"]
    print("  build {:>3}  {}".format(a.get("version"), a.get("processingState")))
' || warn "取得できませんでした"

    asc versions list --app "$APP_ID" 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin)
print()
for v in d.get("data", []):
    a = v["attributes"]
    print("  {:>6}  {}".format(a.get("versionString"), a.get("appStoreState")))
' || true
}

# ── build pipeline ─────────────────────────────────────────────────────────
resolve_build_number() {
    if [[ -n "$BUILD_NUMBER" ]]; then
        info "指定されたビルド番号: $BUILD_NUMBER"
        return
    fi
    local remote; remote="$(latest_build_number)"
    local local_n; local_n="$(current_build_number)"
    local highest=$(( remote > local_n ? remote : local_n ))
    BUILD_NUMBER=$(( highest + 1 ))
    info "ASC の最新 $remote / ローカル $local_n → 次は $BUILD_NUMBER"
}

archive_and_export() {
    local version="$1" number="$2"

    step "バージョンを設定"
    [[ -n "$MARKETING_VERSION" ]] && set_marketing_version "$MARKETING_VERSION"
    set_build_number "$number"
    ok "$version (build $number)"

    verify_profile_matches_certificate "WizMark AppStore V2"
    verify_profile_matches_certificate "WizMarkShare AppStore V2"

    step "アーカイブ"
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    ensure_project_generated
    # -derivedDataPath shares the SPM checkouts and module cache with
    # preflight.sh; without it this archive resolved and rebuilt every package
    # from scratch.
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
        -destination 'generic/platform=iOS' \
        -archivePath "$BUILD_DIR/WizMark.xcarchive" \
        -derivedDataPath "$DERIVED_DATA" \
        OTHER_CODE_SIGN_FLAGS="--keychain $HOME/Library/Keychains/${SIGNING_KEYCHAIN}-db" \
        archive > "$BUILD_DIR/archive.log" 2>&1 || true
    assert_build_marker "$BUILD_DIR/archive.log" \
        '** ARCHIVE SUCCEEDED **' '** ARCHIVE FAILED **' "アーカイブ"

    step "エクスポート"
    # No -derivedDataPath here: xcodebuild rejects it alongside -exportArchive
    # ("The flag -scheme, -testProductsPath, or -xctestrun is required when
    # specifying -derivedDataPath"). Export only repackages the archive, so
    # there is no compilation cache to share anyway.
    xcodebuild -exportArchive \
        -archivePath "$BUILD_DIR/WizMark.xcarchive" \
        -exportPath "$BUILD_DIR/export" \
        -exportOptionsPlist ExportOptions.plist > "$BUILD_DIR/export.log" 2>&1 || true
    assert_build_marker "$BUILD_DIR/export.log" \
        '** EXPORT SUCCEEDED **' '** EXPORT FAILED **' "エクスポート"
    ok "$(ls -lh "$BUILD_DIR/export/WizMark.ipa" | awk '{print $5}')"

    # Sign in with Apple は entitlement が無いとボタンが死ぬだけで、
    # ClerkKitUI はその失敗をユーザーのキャンセルとして握りつぶす。
    # build 22 がそれで壊れたまま配信された。ここで気付けるようにする。
    step "entitlement を確認"
    local ent
    ent="$(codesign -d --entitlements :- "$BUILD_DIR/WizMark.xcarchive/Products/Applications/WizMark.app" 2>/dev/null \
        | plutil -convert xml1 -o - - 2>/dev/null)"
    if grep -q 'com.apple.developer.applesignin' <<<"$ent"; then
        ok "com.apple.developer.applesignin"
    else
        die "com.apple.developer.applesignin がバイナリにありません。Apple サインインが無反応になります"
    fi

    if command -v greenlight >/dev/null 2>&1; then
        step "IPA を検査"
        greenlight ipa "$BUILD_DIR/export/WizMark.ipa" 2>&1 | grep -E "GREENLIT|CRITICAL|WARN" | head -5 || true
    fi
}

upload_and_wait() {
    local number="$1"

    # App Store Connect takes a few minutes to list a build after accepting it,
    # so an interrupted run looks exactly like one that never uploaded. Sending
    # it again earns ITMS-90189 and an email from Apple. Ask first.
    step "アップロード済みか確認"
    local existing; existing="$(build_state "$number")"
    if [[ -n "$existing" ]]; then
        BUILD_ID="${existing##* }"
        ok "build $number は既にあります（${existing%% *}）。アップロードを飛ばします"
    else
        step "アップロード"
        asc builds upload --app "$APP_ID" --ipa "$BUILD_DIR/export/WizMark.ipa" \
            || die "アップロードに失敗しました"
        ok "アップロード完了"

        # The same listing delay means the build is not queryable yet; give it a
        # moment before the wait loop starts calling it missing.
        sleep 30
    fi

    step "処理を待機"
    local waited=0
    while (( waited < 1800 )); do
        local result; result="$(build_state "$number")"
        local state="${result%% *}"
        if [[ -n "$state" && "$state" != "PROCESSING" ]]; then
            [[ "$state" == "VALID" ]] || die "処理結果が $state です"
            ok "VALID  (${waited}s)"
            BUILD_ID="${result##* }"
            return
        fi
        sleep 30; waited=$(( waited + 30 ))
        printf '  %s待機中 %ds%s\r' "$C_DIM" "$waited" "$C_RESET"
    done
    die "30 分待っても処理が完了しませんでした"
}

# ── commands ───────────────────────────────────────────────────────────────
cmd_testflight() {
    resolve_build_number
    local version; version="${MARKETING_VERSION:-$(current_marketing_version)}"

    [[ "$SKIP_PREFLIGHT" == "1" ]] || "$REPO_ROOT/scripts/preflight.sh" --quick

    trap restore_signing EXIT INT TERM HUP
    prepare_signing
    archive_and_export "$version" "$BUILD_NUMBER"

    if [[ "$DRY_RUN" == "1" ]]; then
        step "--dry-run のためここで停止"
        info "IPA: $BUILD_DIR/export/WizMark.ipa"
        return
    fi

    upload_and_wait "$BUILD_NUMBER"

    step "TestFlight へ配信"
    asc builds update --app "$APP_ID" --latest --uses-non-exempt-encryption=false >/dev/null
    asc builds add-groups --app "$APP_ID" --latest --group "$TESTFLIGHT_INTERNAL_GROUP" >/dev/null
    ok "Internal Testers に配信"

    step "完了: $version (build $BUILD_NUMBER)"
}

cmd_submit() {
    [[ -n "$MARKETING_VERSION" ]] || die "--version を指定してください（例: --version 1.0.2）"

    resolve_build_number
    [[ "$SKIP_PREFLIGHT" == "1" ]] || "$REPO_ROOT/scripts/preflight.sh"

    trap restore_signing EXIT INT TERM HUP
    prepare_signing
    archive_and_export "$MARKETING_VERSION" "$BUILD_NUMBER"

    if [[ "$DRY_RUN" == "1" ]]; then
        step "--dry-run のためここで停止"
        return
    fi

    upload_and_wait "$BUILD_NUMBER"

    step "App Store バージョンを用意"
    local version_id
    version_id="$(asc versions list --app "$APP_ID" 2>/dev/null | python3 -c "
import json, sys
d = json.load(sys.stdin)
for v in d.get('data', []):
    if v['attributes'].get('versionString') == '$MARKETING_VERSION':
        print(v['id']); break
")"
    if [[ -z "$version_id" ]]; then
        asc versions create --app "$APP_ID" --version "$MARKETING_VERSION" \
            --platform IOS --copy-metadata-from "$(latest_store_version)" >/dev/null
        version_id="$(asc versions list --app "$APP_ID" 2>/dev/null | python3 -c "
import json, sys
d = json.load(sys.stdin)
for v in d.get('data', []):
    if v['attributes'].get('versionString') == '$MARKETING_VERSION':
        print(v['id']); break
")"
        ok "$MARKETING_VERSION を作成"
    else
        ok "$MARKETING_VERSION は作成済み"
    fi
    [[ -n "$version_id" ]] || die "バージョン ID を取得できません"

    # review doctor は「このバージョンのビルドを選んでください」で止まるが、
    # この流れの中でビルドを紐付けているところが無かった。review submit に
    # --build を渡すのは診断の後なので間に合わない。build 24 がここで止まった。
    step "ビルドを紐付け"
    asc versions attach-build --version-id "$version_id" --build "$BUILD_ID" >/dev/null \
        || die "ビルドの紐付けに失敗しました"
    ok "build $BUILD_NUMBER → $MARKETING_VERSION"

    step "審査前の診断"
    asc review doctor --app "$APP_ID" 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin)
s = d.get("summary", {})
print("  errors={} warnings={} blocking={}".format(
    s.get("errors"), s.get("warnings"), s.get("blocking")))
print("  " + str(d.get("nextAction")))
if s.get("blocking"):
    raise SystemExit(1)
' || die "提出ブロッカーがあります"

    step "審査へ提出"
    warn "提出後は Apple の審査が始まります"
    asc review submit --app "$APP_ID" --version "$MARKETING_VERSION" \
        --build "$BUILD_ID" --confirm || die "提出に失敗しました"
    ok "提出しました"

    step "完了: $MARKETING_VERSION (build $BUILD_NUMBER)"
}

# Recovering by hand after an interrupted run, which leaves the signing
# keychain as the default and affects every other project's builds.
cmd_reset() {
    step "署名環境を戻す"
    security default-keychain -d user -s login.keychain
    security list-keychains -d user -s login.keychain "$SIGNING_KEYCHAIN"
    ok "既定: $(security default-keychain -d user | tr -d ' \"')"
}

case "$COMMAND" in
    status)     show_status ;;
    reset)      cmd_reset ;;
    testflight) cmd_testflight ;;
    submit)     cmd_submit ;;
    *) die "不明なコマンド: ${COMMAND}（status | reset | testflight | submit）" ;;
esac
