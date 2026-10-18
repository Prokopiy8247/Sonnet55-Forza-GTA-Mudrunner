#!/usr/bin/env bash
# Run Unity PlayMode/EditMode tests in batch mode (via ub.sh, i.e. with the project lock) and print a compact summary.
#   Tools/rt.sh <logname> <test filter (name/regex, "" = all)> [PlayMode|EditMode]
# Env: GFX=1 to render (no -nographics). MAXLINES limits [MudRunner] lines printed. VERBOSE=1 lists passed tests too.
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
NAME="${1:?name}"; FILTER="${2:-}"; PLAT="${3:-PlayMode}"
XMLW="$(cygpath -w "$ROOT/Logs/cli/$NAME.xml")"
rm -f "$ROOT/Logs/cli/$NAME.xml"
ARGS=(-runTests -testPlatform "$PLAT" -testResults "$XMLW")
[ -n "$FILTER" ] && ARGS+=(-testFilter "$FILTER")
NOQUIT=1 "$HERE/ub.sh" "$NAME" - "${ARGS[@]}"
python -I "$HERE/test_summary.py" "$ROOT/Logs/cli/$NAME.xml" ${VERBOSE:+-v}
