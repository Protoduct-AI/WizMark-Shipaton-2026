#!/usr/bin/env bash
# Collects the licence of every Swift package the app links and writes them into
# a resource the app ships.
#
#   scripts/generate-licenses.sh
#
# MIT and Apache-2.0 both require the licence text to travel with the binary, so
# this cannot be a link to a website — the text has to be in the app. Generating
# it from the resolved checkouts rather than maintaining a list by hand means a
# new dependency cannot be forgotten.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CHECKOUTS="build/DerivedData/SourcePackages/checkouts"
OUTPUT="Sources/WizMark/Resources/OpenSourceLicenses.json"

# A resolved checkout is needed to read the licences; a plain build produces one.
if [[ ! -d "$CHECKOUTS" ]]; then
    CHECKOUTS="DerivedData/SourcePackages/checkouts"
fi
[[ -d "$CHECKOUTS" ]] || die "パッケージのチェックアウトが見つかりません。先にビルドしてください"

step "ライセンスを収集"

python3 - "$CHECKOUTS" "$OUTPUT" <<'PY'
import json, pathlib, re, sys

checkouts = pathlib.Path(sys.argv[1])
output = pathlib.Path(sys.argv[2])

# Display names for packages whose directory name is not what anyone calls them.
DISPLAY_NAMES = {
    "swift-package-manager-google-mobile-ads": "Google Mobile Ads",
    "swift-package-manager-google-user-messaging-platform": "Google User Messaging Platform",
    "purchases-ios": "RevenueCat",
    "posthog-ios": "PostHog",
    "sentry-cocoa": "Sentry",
    "clerk-ios": "Clerk",
    "clerk-convex-swift": "Clerk for Convex",
    "convex-swift": "Convex",
    "humation-swift": "Humation",
}

def licence_kind(text: str) -> str:
    head = "\n".join(text.splitlines()[:4]).lower()
    if "mit license" in head:
        return "MIT"
    if "apache license" in head:
        return "Apache-2.0"
    if "bsd" in head:
        return "BSD"
    if "isc license" in head:
        return "ISC"
    return "その他"

def copyright_line(text: str) -> str | None:
    for line in text.splitlines():
        stripped = line.strip()
        # Apache's own boilerplate mentions the word without being a notice.
        if re.match(r"copyright\s*(\(c\)|©)", stripped, re.I):
            return stripped
    return None

entries = []
for directory in sorted(checkouts.iterdir()):
    if not directory.is_dir():
        continue

    licence_file = next(
        (p for p in directory.glob("*") if p.is_file() and p.name.upper().startswith(("LICENSE", "COPYING"))),
        None,
    )
    if licence_file is None:
        continue

    text = licence_file.read_text(errors="replace").strip()
    notice_file = next(
        (p for p in directory.glob("*") if p.is_file() and p.name.upper().startswith("NOTICE")),
        None,
    )

    entries.append({
        "name": DISPLAY_NAMES.get(directory.name, directory.name),
        "kind": licence_kind(text),
        "copyright": copyright_line(text),
        "text": text,
        # Apache-2.0 requires any NOTICE to be reproduced alongside the licence.
        "notice": notice_file.read_text(errors="replace").strip() if notice_file else None,
    })

output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(entries, ensure_ascii=False, indent=2) + "\n")
print(f"  {len(entries)} 件を {output} に書き出しました")
for e in entries:
    mark = " +NOTICE" if e["notice"] else ""
    print(f"    {e['name']:<34} {e['kind']}{mark}")
PY

ok "完了"
