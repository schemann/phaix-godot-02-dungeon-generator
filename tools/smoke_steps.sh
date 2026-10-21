#!/usr/bin/env bash
# Runs every step's main scene headless for 120 frames and fails on any
# ERROR, SCRIPT ERROR or WARNING line (the project treats a warning as a bug).
# Usage: tools/smoke_steps.sh   (from anywhere)
set -u

project="$(cd "$(dirname "$0")/.." && pwd)"
failed=0

for step_dir in "$project"/steps/step_*/; do
	step="$(basename "$step_dir")"
	log="$(godot --headless --path "$project" --quit-after 120 "res://steps/$step/main.tscn" 2>&1)"
	code=$?
	problems="$(printf '%s\n' "$log" | grep -E 'ERROR|WARNING' || true)"
	if [ "$code" -ne 0 ] || [ -n "$problems" ]; then
		echo "FAIL $step (exit $code)"
		printf '%s\n' "$problems" | sed 's/^/     /'
		failed=1
	else
		echo "PASS $step"
	fi
done

exit "$failed"
