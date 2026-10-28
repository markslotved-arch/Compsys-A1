#!/usr/bin/env bash
# Sanity-checks that the multithreaded programs give the same results as the
# single-threaded originals, and that they do not hang (deadlock).
#
# Usage: ./check.sh DIR [NEEDLE]
#
#  * fauxgrep-mt: output lines may be in a different order, so we compare the
#    SORTED output of fauxgrep and fauxgrep-mt -n K.
#  * fhistogram-mt: we compare the final frame (the last 9 lines) of the
#    output after stripping ANSI cursor escapes.
#  * Every run is wrapped in `timeout` so a deadlock shows up as a failure.

set -uo pipefail
cd "$(dirname "$0")"

DIR="${1:?usage: ./check.sh DIR [NEEDLE]}"
NEEDLE="${2:-malloc}"
THREADS="1 2 4 8 16"
LIMIT=120   # seconds before a run counts as hung

[ -d "$DIR" ] && [ -n "$(find -L "$DIR" -type f | head -1)" ] || { echo "no files in $DIR - run gen_testdata.sh first"; exit 1; }
make >/dev/null || { echo "make failed"; exit 1; }

strip_ansi() { perl -pe 's/\e\[[0-9]*[A-Za-z]//g'; }
# Portable timeout (macOS has none): killed by SIGALRM -> exit status 142.
tmo() { perl -e 'alarm shift; exec @ARGV' "$@"; }
fail=0
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

echo "== fauxgrep vs fauxgrep-mt (needle: $NEEDLE) =="
tmo "$LIMIT" ./fauxgrep "$NEEDLE" "$DIR" 2>/dev/null | sort > "$tmp/grep_ref"
echo "reference matches: $(wc -l < "$tmp/grep_ref")"
for k in $THREADS; do
  tmo "$LIMIT" ./fauxgrep-mt -n "$k" "$NEEDLE" "$DIR" 2>/dev/null | sort > "$tmp/grep_mt"
  rc=${PIPESTATUS[0]}
  if [ "$rc" -eq 142 ]; then echo "  -n $k: TIMEOUT (deadlock?)"; fail=1
  elif cmp -s "$tmp/grep_ref" "$tmp/grep_mt"; then echo "  -n $k: OK"
  else echo "  -n $k: MISMATCH"; diff "$tmp/grep_ref" "$tmp/grep_mt" | head -5; fail=1; fi
done

echo "== fhistogram vs fhistogram-mt =="
tmo "$LIMIT" ./fhistogram "$DIR" 2>/dev/null | strip_ansi | tail -n 9 > "$tmp/hist_ref"
cat "$tmp/hist_ref"
for k in $THREADS; do
  tmo "$LIMIT" ./fhistogram-mt -n "$k" "$DIR" 2>/dev/null | strip_ansi | tail -n 9 > "$tmp/hist_mt"
  rc=${PIPESTATUS[0]}
  if [ "$rc" -eq 142 ]; then echo "  -n $k: TIMEOUT (deadlock?)"; fail=1
  elif cmp -s "$tmp/hist_ref" "$tmp/hist_mt"; then echo "  -n $k: OK"
  else echo "  -n $k: MISMATCH"; diff "$tmp/hist_ref" "$tmp/hist_mt" | head -5; fail=1; fi
done

[ "$fail" -eq 0 ] && echo "ALL CHECKS PASSED" || echo "SOME CHECKS FAILED"
exit "$fail"