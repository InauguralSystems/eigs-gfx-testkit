#!/usr/bin/env bash
# Planted-fault check for tests/test_gfx_testkit.eigs. For each stub, a
# copy of the package is made in which that one stub silently drops its
# call (its _gfxtk_out / _gfxtk_bump line is deleted, so it still returns
# normally). The unit tests must go RED on every plant, and GREEN on the
# untouched copy (the control), or this script fails. The copies are
# staged with eigs.json beside them (EigenScript #1106).
set -euo pipefail

EIGS="${EIGENSCRIPT:-eigenscript}"
ROOT="$(pwd)"
PKG_NAME="$(python3 -c 'import json;print(json.load(open("eigs.json"))["name"])')"
STUBS="gfx_open gfx_close gfx_clear gfx_rect gfx_rrect gfx_line gfx_point gfx_circle gfx_text gfx_clip gfx_present gfx_poll gfx_delay gfx_ticks gfx_text_width gfx_text_height win_key"

TMP="$(mktemp -d)"
trap "rm -rf '$TMP'" EXIT

stage() {
    rm -rf "$TMP/pkg"
    mkdir -p "$TMP/pkg/tests"
    cp -a "$ROOT/eigs.json" "$ROOT/$PKG_NAME.eigs" "$TMP/pkg/"
    cp -a "$ROOT/tests/test_gfx_testkit.eigs" "$TMP/pkg/tests/"
}

# Delete the first _gfxtk_out/_gfxtk_bump line inside `define <stub>(`.
plant() {
    python3 - "$TMP/pkg/$PKG_NAME.eigs" "$1" <<'PY'
import sys
path, stub = sys.argv[1], sys.argv[2]
lines = open(path).read().split("\n")
inside = False
for i, line in enumerate(lines):
    if line.startswith("define " + stub + "("):
        inside = True
        continue
    if inside and line.startswith("define "):
        break
    if inside and ("_gfxtk_out of" in line or "_gfxtk_bump of" in line):
        del lines[i]
        open(path, "w").write("\n".join(lines))
        sys.exit(0)
sys.exit("plant: no recording line found in " + stub)
PY
}

stage
if ! (cd "$TMP/pkg/tests" && "$EIGS" test_gfx_testkit.eigs > "$TMP/out" 2>&1); then
    echo "FAIL: control (no plant) is red:"; cat "$TMP/out"; exit 1
fi
echo "PASS: control is green"

bad=0
for s in $STUBS; do
    stage
    plant "$s"
    if (cd "$TMP/pkg/tests" && "$EIGS" test_gfx_testkit.eigs > "$TMP/out" 2>&1); then
        echo "FAIL: $s drops its call and the tests stay green"
        bad=1
    else
        echo "PASS: $s dropping its call turns the tests red ($(grep -c '^FAIL' "$TMP/out") failing check(s))"
    fi
done
exit $bad
