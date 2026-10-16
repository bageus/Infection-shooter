#!/usr/bin/env bash
# Run inside xvfb-run: EWMH fullscreen requests need a real window manager.
set -euo pipefail
display_renderer=${1:?Expected renderer argument}
display_wm_log=${DISPLAY_WM_LOG:-/tmp/display-wm.log}
openbox --sm-disable > "$display_wm_log" 2>&1 &
display_wm_pid=$!
cleanup_display_wm() {
  kill "$display_wm_pid" 2>/dev/null || true
  wait "$display_wm_pid" 2>/dev/null || true
}
trap cleanup_display_wm EXIT
display_wm_ready=false
for display_attempt in $(seq 1 50); do
  if ! kill -0 "$display_wm_pid" 2>/dev/null; then
    cat "$display_wm_log"
    exit 1
  fi
  if xprop -root _NET_SUPPORTING_WM_CHECK 2>/dev/null | grep -q 'window id #'; then
    display_wm_ready=true
    break
  fi
  sleep 0.1
done
if [ "$display_wm_ready" != true ]; then
  echo 'Window manager did not become ready for native display tests.' >&2
  cat "$display_wm_log"
  exit 1
fi
godot --path . --audio-driver Dummy --rendering-method "$display_renderer" --script game/bootstrap/app/tests/run_display_settings_tests.gd
