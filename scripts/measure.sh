#!/bin/zsh
set -euo pipefail

PID="$(pgrep -f 'macmon.app/Contents/MacOS/macmon' | head -1 || true)"
if [[ -z "$PID" ]]; then
    echo "macmon is not running"
    exit 1
fi

echo "pid $PID"
ps -o rss=,%cpu=,comm= -p "$PID"
echo
footprint -p "$PID" | sed -n '1,12p'

echo
echo "sampling idle CPU for 20s..."
CPU=$( (top -l 2 -s 10 -pid "$PID" -stats cpu 2>/dev/null | tail -1) || true )
echo "top: $CPU"
echo
echo "gates: footprint <= 24 MB, idle CPU <= 0.3%, dirty <= 8 MB"
