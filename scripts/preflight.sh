#!/usr/bin/env bash
# Everything that should pass before a build is worth uploading.
#
#   scripts/preflight.sh           全チェック
#   scripts/preflight.sh --quick   ビルドとテストのみ（審査系を省く）
#
# Exits non-zero on the first failure so it can gate the release script.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

QUICK=0
[[ "${1:-}" == "--quick" ]] && QUICK=1

SIMULATOR="$(resolve_simulator)"

require_cmd xcodegen "brew install xcodegen"
require_cmd xcodebuild "Xcode をインストールしてください"

muted "シミュレータ: $SIMULATOR"

step "プロジェクトを生成"
ensure_project_generated

step "ビルド"
xcodebuild build \
    -project "$PROJECT" -scheme "$SCHEME" \
    -destination "$SIMULATOR" -configuration Debug \
    -derivedDataPath "$DERIVED_DATA" > build/preflight-build.log 2>&1 || true
assert_build_marker build/preflight-build.log \
    '** BUILD SUCCEEDED **' '** BUILD FAILED **' "ビルド"

step "テスト"
xcodebuild test \
    -project "$PROJECT" -scheme "$SCHEME" \
    -destination "$SIMULATOR" -configuration Debug \
    -derivedDataPath "$DERIVED_DATA" > build/preflight-test.log 2>&1 || true
assert_build_marker build/preflight-test.log \
    '** TEST SUCCEEDED **' '** TEST FAILED **' "テスト" \
    "Test Case.*failed|error: "
ok "$(grep -cE "Test Case .* passed" build/preflight-test.log | tr -d ' ') 件のテストが成功"

step "Convex の型チェック"
if [[ -f convex/tsconfig.json ]]; then
    npx tsc --noEmit -p convex/tsconfig.json || die "Convex の型エラー"
    ok "型エラーなし"
else
    muted "convex/tsconfig.json がないため省略"
fi

# Mutations whose result the app discards must return null: ConvexMobile's
# no-result mutation overload decodes the response as String?, so an object
# fails at the decoder even though the mutation already succeeded server-side.
step "Convex の戻り値契約"
python3 - <<'PY' || die "戻り値の契約に違反しています"
import pathlib, re, sys

# Every service, every convex module: scoping this to shares.ts is how the
# avatar save in users.ts shipped broken.
discarded = {}
for f in sorted(pathlib.Path('Sources').rglob('*.swift')):
    for m in re.finditer(
            r'^[ \t]*try await client\.mutation\(\s*\n?\s*"(\w+):(\w+)"',
            f.read_text(), re.M):
        discarded.setdefault((m.group(1), m.group(2)), f)

bad, checked = [], []
for (module, name), _ in sorted(discarded.items()):
    ts = pathlib.Path(f'convex/{module}.ts')
    if not ts.exists():
        continue
    ts_src = ts.read_text()
    m = re.search(rf'export const {name} = mutation\(', ts_src)
    if not m:
        continue
    start = m.end()
    nxt = ts_src.find('\nexport const', start)
    body = ts_src[start: nxt if nxt > 0 else len(ts_src)]
    checked.append(f'{module}:{name}')
    for r in re.findall(r'^\s*return (.+?);', body, re.M):
        if not r.strip().startswith('null'):
            bad.append(f'{module}:{name} が {r.strip()} を返しています')

if bad:
    for b in bad:
        print(f'  {b}')
    print('  戻り値を読まない mutation は null を返す必要があります')
    sys.exit(1)
print('  検査した mutation:', ', '.join(checked) or 'なし')
PY
ok "戻り値の契約を満たしています"

if [[ "$QUICK" == "1" ]]; then
    step "完了（--quick）"
    exit 0
fi

# A dependency added without regenerating this ships without its licence,
# which MIT and Apache-2.0 both forbid.
step "ライセンス一覧の鮮度"
if [[ -f Sources/WizMark/Resources/OpenSourceLicenses.json ]]; then
    before="$(shasum Sources/WizMark/Resources/OpenSourceLicenses.json | cut -d' ' -f1)"
    "$REPO_ROOT/scripts/generate-licenses.sh" >/dev/null 2>&1 || true
    after="$(shasum Sources/WizMark/Resources/OpenSourceLicenses.json | cut -d' ' -f1)"
    if [[ "$before" != "$after" ]]; then
        warn "ライセンス一覧を更新しました。コミットしてください"
    else
        ok "最新です"
    fi
else
    warn "ライセンス一覧がありません（scripts/generate-licenses.sh）"
fi

step "App Store コンプライアンス"
if command -v greenlight >/dev/null 2>&1; then
    greenlight preflight . 2>&1 | tail -25
    muted "placeholder: と launch storyboard の指摘は既知の誤検知です"
else
    muted "greenlight 未導入のため省略 (brew install revylai/tap/greenlight)"
fi

# check.sh と同じ判定を使う。以前ここに書き写した版は接頭辞だけに一致し、
# それを探すスクリプト自身を検出していた。
step "秘密情報の混入"
"$REPO_ROOT/scripts/check.sh" --all >/dev/null || die "高速検査に失敗しました"
ok "検出なし"

step "すべて通過"
