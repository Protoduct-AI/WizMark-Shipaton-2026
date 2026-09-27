#!/usr/bin/env bash
# Fast checks — no build, no simulator, no network. Runs in about a second.
#
#   scripts/check.sh          変更のあるファイルだけを見る
#   scripts/check.sh --all    リポジトリ全体を見る
#
# This is what the pre-commit hook runs, so it must stay fast enough that
# nobody is tempted to skip it.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ALL=0
[[ "${1:-}" == "--all" ]] && ALL=1

failed=0
fail() { printf '  %s✗%s %s\n' "$C_RED" "$C_RESET" "$*"; failed=1; }

# ── 秘密情報 ───────────────────────────────────────────────────────────────
# Live keys and cloud credentials. Publishable keys (pk_live) are meant to ship
# in the client, so they are not flagged.
step "秘密情報"
# A secret is only a secret when it carries a value. Matching the prefix alone
# flags the scanners that look for it — including this file.
secret_pattern='(sk_live_[A-Za-z0-9]{8,}|sk_test_[A-Za-z0-9]{8,}|AIza[0-9A-Za-z_-]{30,}|AKIA[0-9A-Z]{16}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----)'
if git grep -nE "$secret_pattern" -- \
        'Sources/*' 'convex/*' 'web/src/*' '*.plist' \
        ':!scripts/*' ':!.github/*' 2>/dev/null; then
    fail "秘密情報らしき文字列が含まれています"
else
    ok "検出なし"
fi

# ── Convex の戻り値契約 ────────────────────────────────────────────────────
# ConvexMobile's no-result mutation overload decodes the response as String?,
# Covers every convex module reached from any service, not just shares: the
# avatar save in users.ts broke exactly because the check only looked there.
# so a mutation whose result the app discards must return null. Returning an
# object fails in the client decoder on a call the server already committed —
# the user sees a generic "data is not in the correct format" for an operation
# that actually worked.
step "Convex の戻り値契約"
if python3 - <<'PY'
import pathlib, re, sys

# A call is "discarding" when the statement starts with `try await`; the typed
# form binds the result (`let x: T = try await ...`) and is fine.
discarded = {}
for f in sorted(pathlib.Path('Sources').rglob('*.swift')):
    src = f.read_text()
    for m in re.finditer(
            r'^[ \t]*try await client\.mutation\(\s*\n?\s*"(\w+):(\w+)"', src, re.M):
        discarded.setdefault((m.group(1), m.group(2)), f)

bad, checked = [], []
for (module, name), f in sorted(discarded.items()):
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
    print('\n'.join('    ' + b for b in bad))
    sys.exit(1)
print('    ' + (', '.join(checked) or 'なし'))
PY
then
    ok "結果を読まない mutation はすべて null 返し"
else
    fail "結果を読まない mutation は null を返してください"
fi

# ── デバッグ出力 ───────────────────────────────────────────────────────────
step "デバッグ出力"
targets=()
if [[ "$ALL" == "1" ]]; then
    while IFS= read -r f; do targets+=("$f"); done < <(git ls-files 'Sources/*.swift')
else
    while IFS= read -r f; do
        [[ -f "$f" && "$f" == Sources/*.swift ]] && targets+=("$f")
    done < <(git diff --cached --name-only --diff-filter=ACM; git diff --name-only)
fi

if [[ ${#targets[@]} -eq 0 ]]; then
    muted "対象の Swift ファイルなし"
else
    # print() in shipping code should be os.Logger instead. Tests and previews
    # are exempt.
    hits="$(grep -nE '^\s*print\(' "${targets[@]}" 2>/dev/null \
        | grep -vE '(Tests?/|#Preview|// *swiftlint)' || true)"
    if [[ -n "$hits" ]]; then
        printf '%s\n' "$hits" | head -10 | sed 's/^/    /'
        warn "print() は os.Logger に置き換えてください（警告のみ）"
    else
        ok "print() なし (${#targets[@]} ファイル)"
    fi
fi

# ── 巨大ファイル ───────────────────────────────────────────────────────────
step "ファイルサイズ"
oversized="$(git ls-files 'Sources/*.swift' | while read -r f; do
    n=$(wc -l < "$f" | tr -d ' ')
    if (( n > 800 )); then
        printf '    %5d 行  %s\n' "$n" "$f"
    fi
done)"
if [[ -n "$oversized" ]]; then
    printf '%s\n' "$oversized"
    warn "800 行を超えています。分割を検討してください（警告のみ）"
else
    ok "すべて 800 行以内"
fi

echo
if [[ "$failed" == "1" ]]; then
    die "検査に失敗しました"
fi
ok "通過"
