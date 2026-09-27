#!/usr/bin/env bash
# Puts the simulator into the state a demo recording starts from.
#
#   scripts/demo.sh prepare   ビルドして入れ直し、デモ用データを投入
#   scripts/demo.sh run       Maestro のフローを流す
#   scripts/demo.sh record    録画しながら流す
#
# The launch arguments are applied here rather than in the Maestro flow,
# because Maestro's launchApp did not pass them through to the app.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Maestro ships its own JRE-less launcher, and this machine has no
# /usr/libexec/java_home entry even though Homebrew provides the JDK.
export JAVA_HOME="${JAVA_HOME:-$(brew --prefix openjdk@21 2>/dev/null)/libexec/openjdk.jdk/Contents/Home}"
export PATH="$JAVA_HOME/bin:$HOME/.maestro/bin:$PATH"

COMMAND="${1:-run}"
APP_PATH="build/DerivedData/Build/Products/Debug-iphonesimulator/WizMark.app"

simulator_udid() {
    resolve_simulator | sed 's/^id=//'
}

cmd_prepare() {
    local udid; udid="$(simulator_udid)"
    step "シミュレータ $udid を準備"

    xcodegen generate >/dev/null
    xcodebuild build -project "$PROJECT" -scheme "$SCHEME" \
        -destination "id=$udid" -configuration Debug \
        -derivedDataPath build/DerivedData > build/demo-build.log 2>&1 || true
    grep -qE '\*\* BUILD SUCCEEDED \*\*' build/demo-build.log \
        || die "ビルドに失敗しました (build/demo-build.log)"
    ok "ビルド完了"

    xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || xcrun simctl boot "$udid" || true
    xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
    xcrun simctl uninstall "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
    xcrun simctl install "$udid" "$APP_PATH" || die "インストールに失敗しました"
    xcrun simctl launch "$udid" "$BUNDLE_ID" -forcePro -seedDemoData >/dev/null \
        || die "起動に失敗しました"
    ok "Pro・デモデータ入りで起動"
    muted "広告なし / コレクション3件 / ブックマーク7件"
}

cmd_run() {
    step "Maestro フローを実行"
    mkdir -p build/demo
    maestro test .maestro/demo.yaml
}

cmd_record() {
    step "録画しながら実行"
    mkdir -p build/demo
    maestro record .maestro/demo.yaml build/demo/wizmark-demo.mp4
}

case "$COMMAND" in
    prepare) cmd_prepare ;;
    run)     cmd_run ;;
    record)  cmd_record ;;
    *) die "不明なコマンド: ${COMMAND}（prepare | run | record）" ;;
esac
