#!/bin/sh
DUR=${1:-240}
TOTAL_KB=$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || echo 4000000)
MB=$(( TOTAL_KB * 92 / 100 / 1024 ))
docker run --rm -d --name tick1-stress-mem polinux/stress \
  stress --vm 1 --vm-bytes "${MB}M" --vm-hang 0 --timeout "${DUR}s"
echo "занял ${MB}M на ${DUR}s, остановить раньше: docker stop tick1-stress-mem"
