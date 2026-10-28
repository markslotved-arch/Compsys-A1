#!/usr/bin/env bash
# Benchmarks fauxgrep / fauxgrep-mt and fhistogram / fhistogram-mt.
#
# Usage: ./bench.sh [-r REPS] [-t "1 2 4 8"] [-s NEEDLE] [-o OUTPREFIX] DIR
#
#   -r REPS       timed repetitions per configuration           (default 5)
#   -t THREADS    space-separated thread counts for the -mt programs
#                                                              (default "1 2 4 8 16")
#   -s NEEDLE     search string for fauxgrep                    (default malloc)
#   -o PREFIX     output file prefix                            (default results)
#
# Produces PREFIX.csv (every individual run) and PREFIX.md (summary table with
# mean/stddev/min wall time, files/s, bytes/s and speedup vs. the
# single-threaded original).

set -euo pipefail
cd "$(dirname "$0")"

REPS=5
THREADS="1 2 4 8 16"
NEEDLE="malloc"
PREFIX="results"

while getopts "r:t:s:o:" opt; do
  case "$opt" in
    r) REPS="$OPTARG" ;;
    t) THREADS="$OPTARG" ;;
    s) NEEDLE="$OPTARG" ;;
    o) PREFIX="$OPTARG" ;;
    *) echo "usage: $0 [-r REPS] [-t \"1 2 4\"] [-s NEEDLE] [-o PREFIX] DIR"; exit 1 ;;
  esac
done
shift $((OPTIND - 1))
DIR="${1:?usage: $0 [options] DIR}"
[ -d "$DIR" ] || { echo "not a directory: $DIR"; exit 1; }

echo "Building..."
make >/dev/null
for b in fauxgrep fauxgrep-mt fhistogram fhistogram-mt; do
  [ -x "./$b" ] || { echo "missing binary ./$b (add it to the Makefile)"; exit 1; }
done

# Same traversal semantics as the programs: follow symlinks, regular files only.
FILES=$(find -L "$DIR" -type f | wc -l)
FILES=$(echo $FILES)   # trim whitespace (BSD wc pads)
BYTES=$(find -L "$DIR" -type f -print0 | xargs -0 cat | wc -c | tr -d " ")
[ "$FILES" -gt 0 ] && [ "$BYTES" -gt 0 ] || { echo "Data set $DIR is empty - run gen_testdata.sh first"; exit 1; }
echo "Data set: $DIR  ($FILES files, $BYTES bytes)"
echo "Threads: $THREADS   Reps: $REPS   Needle: $NEEDLE"
CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu)
echo "CPU cores: $CORES"

# time_run cmd...  -> prints elapsed wall seconds (sub-second precision).
# Portable (macOS + Linux): perl's Time::HiRes does the timing around the
# command, so perl's own start-up time is not included. The command's
# stdout/stderr go to /dev/null; the time is written to fd 3.
time_run() {
  perl -MTime::HiRes=time -e '
    open(my $o, ">&=", 3) or die; my $s = time;
    system(@ARGV); printf $o "%.6f", time - $s;' "$@" 3>&1 >/dev/null 2>&1
}

CSV="$PREFIX.csv"
echo "family,variant,threads,rep,seconds" > "$CSV"

# bench FAMILY VARIANT THREADS cmd...
bench() {
  local family="$1" variant="$2" threads="$3"; shift 3
  "$@" >/dev/null 2>&1 || true            # warm-up (untimed)
  for r in $(seq 1 "$REPS"); do
    local t; t=$(time_run "$@")
    echo "$family,$variant,$threads,$r,$t" >> "$CSV"
    printf "  %-6s %-3s n=%-3s rep %d: %s s\n" "$family" "$variant" "$threads" "$r" "$t"
  done
}

echo "--- grep family ---"
bench grep st 1 ./fauxgrep "$NEEDLE" "$DIR"
for k in $THREADS; do
  bench grep mt "$k" ./fauxgrep-mt -n "$k" "$NEEDLE" "$DIR"
done

echo "--- histogram family ---"
bench hist st 1 ./fhistogram "$DIR"
for k in $THREADS; do
  bench hist mt "$k" ./fhistogram-mt -n "$k" "$DIR"
done

# ---- Summary ----
MD="$PREFIX.md"
awk -F, -v files="$FILES" -v bytes="$BYTES" '
  NR == 1 { next }
  {
    key = $1 "," $2 "," $3
    if (!(key in n)) { order[++m] = key; min[key] = $5; fam[key] = $1; var[key] = $2; thr[key] = $3 }
    n[key]++; sum[key] += $5; sq[key] += $5 * $5
    if ($5 < min[key]) min[key] = $5
  }
  END {
    for (i = 1; i <= m; i++) {
      k = order[i]
      mean[k] = sum[k] / n[k]
      if (var[k] == "st") base[fam[k]] = mean[k]
    }
    print "| program | threads | mean (s) | stddev (s) | min (s) | files/s | MB/s | speedup |"
    print "|---|---|---|---|---|---|---|---|"
    for (i = 1; i <= m; i++) {
      k = order[i]
      v = sq[k] / n[k] - mean[k] * mean[k]; if (v < 0) v = 0
      name = (fam[k] == "grep" ? "fauxgrep" : "fhistogram") (var[k] == "mt" ? "-mt" : "")
      th = (var[k] == "mt" ? thr[k] : "-")
      printf "| %s | %s | %.3f | %.3f | %.3f | %.2f | %.1f | %.2fx |\n",
        name, th, mean[k], sqrt(v), min[k], files / mean[k], bytes / mean[k] / 1e6, base[fam[k]] / mean[k]
    }
  }' "$CSV" > "$MD"

echo
echo "Data set: $DIR ($FILES files, $BYTES bytes), $CORES cores"
cat "$MD"
echo
echo "Raw runs: $CSV    Summary table: $MD"