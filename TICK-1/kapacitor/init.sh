#!/bin/sh
# грузит tick-скрипты и хендлеры в kapacitor и включает
# имя файла: <тип>_<имя>.tick, например batch_cpu_high.tick -> задача cpu_high
set -u

echo "[init] жду kapacitor (${KAPACITOR_URL})"
until kapacitor list tasks >/dev/null 2>&1; do sleep 2; done
echo "[init] kapacitor поднялся"

for f in /tasks/*.tick; do
  base=$(basename "$f" .tick)
  type=${base%%_*}
  name=${base#*_}
  echo "[init] define task '$name' (type=$type)"
  kapacitor define "$name" -type "$type" -tick "$f" -dbrp telegraf.autogen || exit 1
  kapacitor enable "$name" || exit 1
done

for h in /handlers/*.yaml; do
  [ -e "$h" ] || continue
  echo "[init] define topic handler $h"
  kapacitor define-topic-handler "$h" || exit 1
done

if [ "${TELEGRAM_ENABLED:-false}" = "true" ]; then
  for h in /handlers/optional/telegram.yaml; do
    echo "[init] define topic handler $h"
    kapacitor define-topic-handler "$h" || exit 1
  done
fi

echo "[init] готово"
kapacitor list tasks
