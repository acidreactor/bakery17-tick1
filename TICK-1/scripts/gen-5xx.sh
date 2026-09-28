#!/bin/sh
PORT=${NGINX_PORT:-8080}
docker compose stop mysql
for i in $(seq 1 30); do
  curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:${PORT}/"
  sleep 1
done
echo "поднять обратно: docker compose start mysql"
