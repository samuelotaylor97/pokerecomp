#!/bin/sh
# Runtime half of the Crystal Complete gate. The synthetic half is GUT.
# Exit 0 when no Crystal cache is loaded: that is not a 251 proof.
# Exit 1 when a cache is loaded and the live walk is short of 251.
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
godot="${GODOT_BIN:-godot}"
out="${1:-/tmp/crystal-complete-251.md}"
status=0
GODOT_CAP="${GODOT_CAP:-180}" tools/ci_godot.sh "$godot" --headless --path . \
	-s res://tools/crystal_complete_report.gd -- "$out" || status=$?
if [ "$status" -eq 2 ]; then
	echo "Crystal cache absent. Runtime coverage did not prove all 251."
	exit 0
fi
if [ "$status" -ne 0 ]; then
	echo "Crystal Complete live coverage failed. See $out"
	exit 1
fi
echo "Crystal Complete live coverage proved all 251 from the open cache."
exit 0
