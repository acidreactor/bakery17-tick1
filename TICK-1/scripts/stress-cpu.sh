#!/bin/sh
DUR=${1:-240}
docker run --rm -d --name tick1-stress-cpu polinux/stress \
  stress --cpu "$(nproc)" --timeout "${DUR}s"
echo "стресс на ${DUR}s, остановить раньше: docker stop tick1-stress-cpu"
