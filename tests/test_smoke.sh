#!/usr/bin/env bash
# Consumer-shaped smoke test. A throwaway consumer project (its own
# eigs.json, so the resolver has a project root) gets this package staged
# at eigs_modules/<name>/, exactly where `--pkg add` puts it. A test file in
# a SUBDIRECTORY then does `load_file of "<name>.eigs"`, which must resolve
# through the eigs_modules walk, and loads the real lib/ui.eigs over the
# stubs. Two runs: metrics on (the stubbed bitmap math) and metrics off
# (the toolkit's own fallback), which must lay out identically.
set -euo pipefail

EIGS="${EIGENSCRIPT:-eigenscript}"
PKG_NAME="$(python3 -c 'import json;print(json.load(open("eigs.json"))["name"])')"
PKG_ROOT="$(pwd)"

TMP="$(mktemp -d)"
trap "rm -rf '$TMP'" EXIT

echo '{"name": "consumer", "version": "0.0.0", "deps": {}}' > "$TMP/eigs.json"
mkdir -p "$TMP/eigs_modules/$PKG_NAME" "$TMP/test"
cp -a "$PKG_ROOT/$PKG_NAME.eigs" "$PKG_ROOT/eigs.json" "$TMP/eigs_modules/$PKG_NAME/"

run_case() {
    local metrics="$1"
    cat > "$TMP/test/app_test.eigs" <<EOF
load_file of "$PKG_NAME.eigs"
gfx_testkit_metrics of $metrics
load_file of "lib/ui.eigs"
clicks is {"n": 0}
define on_click(w) as:
    clicks.n is clicks.n + 1
    return null
b is button of ["b1", 10, 20, 80, 30, "Click", on_click]
gfx_testkit_record of true
render of [b, 0, 0]
print of ((gfx_testkit_count of "rrect") > 0)
print of ((gfx_testkit_count of "text") > 0)
print of (gfx_testkit_clip of [])
print of (text_width of ["Click", 1])
dispatch of [b, {"type": "mousedown", "button": 1, "x": 20, "y": 30}]
dispatch of [b, {"type": "mouseup", "button": 1, "x": 20, "y": 30}]
dispatch of [b, {"type": "mousedown", "button": 1, "x": 20, "y": 30}]
dispatch of [b, {"type": "mouseup", "button": 1, "x": 20, "y": 30}]
print of clicks.n
EOF
    (cd "$TMP/test" && "$EIGS" app_test.eigs 2>&1)
}

# rrect drawn, text drawn, clip stack balanced, 5 glyphs x 6 px, two clicks
want=$'true\ntrue\nnull\n30\n2'
for m in true false; do
    got="$(run_case "$m")" || { echo "FAIL (metrics $m): consumer run died:"; echo "$got"; exit 1; }
    if [ "$got" != "$want" ]; then
        echo "FAIL (metrics $m): got"; echo "$got"; echo "want"; echo "$want"; exit 1
    fi
    echo "PASS: load_file $PKG_NAME.eigs from eigs_modules drives lib/ui.eigs (metrics $m)"
done
