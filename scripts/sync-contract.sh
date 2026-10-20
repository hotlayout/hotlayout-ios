#!/bin/sh
# Copies the contract artifacts and the shared case tables into this package.
#
#   scripts/sync-contract.sh <path>
#
# <path> is a checkout of the contract: a folder that holds `screen-schema.json`, or a
# repository that holds such a folder as `contract/`.
#
# What it writes:
#  - Tests/HotLayoutTests/Resources/contract/*.json and fixtures/ — the artifacts and tables
#    the tests read (an exact copy);
#  - Demo/fixtures/*.json and themes/ — the screen fixtures the demo app opens (the demo's own
#    `hostile/`, `images/` and `sample-data/` stay);
#  - Sources/HotLayout/Resources/icons.json — the icon set the reader ships with;
#  - Sources/HotLayout/Resources/built-in-theme.json — the `contract` block of theme.json,
#    the theme the reader uses when the host passes none.
#
# The tests compare the shipped mirrors with the copied artifacts, so a sync that changes
# the contract without a matching change in the reader fails `swift test`.
set -eu

here="$(cd "$(dirname "$0")/.." && pwd)"
if [ $# -lt 1 ]; then
  echo "usage: scripts/sync-contract.sh <path to the contract>" >&2
  exit 1
fi
contract="$1"
[ -f "$contract/screen-schema.json" ] || contract="$1/contract"
if [ ! -f "$contract/screen-schema.json" ]; then
  echo "No contract at $1 (no screen-schema.json in it or in its contract/ folder)." >&2
  exit 1
fi

tests="$here/Tests/HotLayoutTests/Resources/contract"
rm -rf "$tests"
mkdir -p "$tests"
cp "$contract"/*.json "$tests/"
cp -R "$contract/fixtures" "$tests/fixtures"

demo="$here/Demo/fixtures"
mkdir -p "$demo"
rm -f "$demo"/*.json
rm -rf "$demo/themes"
cp "$contract"/fixtures/*.json "$demo/"
cp -R "$contract/fixtures/themes" "$demo/themes"

cp "$contract/THIRD-PARTY-NOTICES.md" "$here/THIRD-PARTY-NOTICES.md"

library="$here/Sources/HotLayout/Resources"
mkdir -p "$library"
cp "$contract/icons.json" "$library/icons.json"
python3 - "$contract/theme.json" "$library/built-in-theme.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as source:
    block = json.load(source)["contract"]
with open(sys.argv[2], "w", encoding="utf-8") as target:
    json.dump(block, target, ensure_ascii=False, indent=2)
    target.write("\n")
PY

echo "Synced contract from $contract"
