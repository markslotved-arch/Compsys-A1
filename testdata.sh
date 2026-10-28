#!/usr/bin/env bash
# Generates reproducible-ish synthetic test data for the benchmarks.
#
# Usage: ./gen_testdata.sh [OUTDIR]        (default: testdata)
#
# Two data sets are created, because they stress different things:
#   OUTDIR/many_small/  many small files  -> job queue / per-file overhead dominates
#   OUTDIR/few_large/   a few large files  -> raw read/compute throughput dominates
# Files are base64 text (so line-based fauxgrep has real lines to work on),
# with the line "p = malloc(n);" inserted every 1000 lines so that the needle
# "malloc" produces some matches.
#
# Sizes can be overridden with environment variables:
#   SMALL_FILES (default 2000)  SMALL_KB (default 20)
#   LARGE_FILES (default 8)     LARGE_MB (default 32)

set -euo pipefail

OUT="${1:-testdata}"
SMALL_FILES="${SMALL_FILES:-2000}"
SMALL_KB="${SMALL_KB:-20}"
LARGE_FILES="${LARGE_FILES:-8}"
LARGE_MB="${LARGE_MB:-32}"

make_file() {  # make_file PATH BYTES
  head -c "$2" /dev/urandom | base64 | fold -w 76 \
    | awk 'NR % 100 == 0 { print "p = malloc(n);" } { print }' > "$1"
}

mkdir -p "$OUT/many_small" "$OUT/few_large"

echo "Generating $SMALL_FILES small files (~${SMALL_KB} KB each)..."
for i in $(seq 1 "$SMALL_FILES"); do
  sub="$OUT/many_small/dir$((i % 20))"
  mkdir -p "$sub"
  make_file "$sub/file$i.txt" $((SMALL_KB * 1024))
done

echo "Generating $LARGE_FILES large files (~${LARGE_MB} MB each)..."
for i in $(seq 1 "$LARGE_FILES"); do
  make_file "$OUT/few_large/big$i.txt" $((LARGE_MB * 1024 * 1024))
done

echo "Done:"
du -sh "$OUT"/*