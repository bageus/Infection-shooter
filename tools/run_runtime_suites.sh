#!/usr/bin/env bash
# Runs headless Godot test suites in parallel and reports each failure as a CI annotation.
# Each suite gets its own XDG_DATA_HOME, so user:// files such as planned_layout.json cannot leak between suites.
# Usage: tools/run_runtime_suites.sh <suite-list> <work-dir> [jobs]
# A suite fails when Godot exits non-zero or its log contains SCRIPT ERROR / ERROR: lines.
set -uo pipefail

list=$1
work=$2
jobs=${3:-4}

# A runner that is killed mid-run leaves no suite annotations, so report how the script ended.
report_exit() {
	local status=$?
	if [ "$status" != 0 ]; then
		echo "::error title=Runner ended::exit $status after ${SECONDS}s, $(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo) MiB available"
	fi
}
trap report_exit EXIT

rm -rf "$work"
mkdir -p "$work/data"

run_one() {
	local suite=$1 work=$2
	local name log data start status elapsed errors limit
	name=$(basename "$suite" .gd)
	log="$work/$name.log"
	data="$work/data/$name"
	mkdir -p "$data"
	# This suite saves and restores the entire authored map (5,000+ objects).
	# Measured at 115-118 s locally and timed out at 121 s on shared CI.
	# Keep its real map/physics assertions and allow normal runner variation.
	limit=120
	if [ "$suite" = "game/bootstrap/app/tests/run_planning_mode_tests.gd" ]; then
		limit=180
	fi
	start=$(date +%s)
	XDG_DATA_HOME="$data" timeout "$limit" godot --headless --path . --script "$suite" > "$log" 2>&1
	status=$?
	elapsed=$(( $(date +%s) - start ))
	echo "$elapsed $suite" >> "$work/timings.txt"
	if [ "$status" != 0 ] || grep -qE 'SCRIPT ERROR|^ERROR:' "$log"; then
		errors=$(grep -E 'SCRIPT ERROR|ERROR|failure|at: ' "$log" | head -6 | tr '\n' ' ' | cut -c1-900)
		echo "::error title=Suite failed::$suite exited $status in ${elapsed}s :: $errors"
		echo "$suite" >> "$work/failed.txt"
	fi
}
export -f run_one

# Suites are independent (each has its own user:// directory), so they run side by side.
xargs -P "$jobs" -I{} bash -c 'run_one "$1" "$2"' _ {} "$work" < "$list"

# Keep the full per-suite output in the job log, in list order, as the sequential loop did.
while read -r suite; do
	cat "$work/$(basename "$suite" .gd).log"
done < "$list"

echo "Slowest suites:"
sort -rn "$work/timings.txt" | head -10

if [ -s "$work/failed.txt" ]; then
	echo "$(wc -l < "$work/failed.txt") suite(s) failed"
	exit 1
fi
echo "All $(wc -l < "$list") suites passed"
