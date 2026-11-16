#!/usr/bin/env bash
# Runs the autoplay QA bot (tools/autoplay_bot.gd); see docs/AUTOPLAY_BOT.md.
# Usage: tools/run_autoplay.sh maps=level_1,level_2 difficulty=all duration=180 [out=<path without extension>]
# RENDER=1 opens a window instead of running headless. Exit code: 0 clean, 1 script errors or a map that failed to load.
set -uo pipefail
log=$(mktemp)
${GODOT:-godot} $([ -z "${RENDER:-}" ] && echo --headless) --fixed-fps 60 --path "$(dirname "$0")/.." --script res://tools/autoplay_bot.gd -- "$@" 2>&1 | tee "$log"
# The engine can abort while shutting down after many missions, so the bot's own verdict decides.
code=$(sed -n 's/^AUTOPLAY exit_code=//p' "$log" | tail -1)
rm -f "$log"
exit "${code:-3}"
