# TICK стек для Булочной №17

Домашнее задание по курсу «Observability: мониторинг, логирование, трассировка».

Тема: Установка и настройка TICK стека (Telegraf, InfluxDB, Chronograf, Kapacitor) для мониторинга CMS.

## Контекст

Булочная открывает второй производственный цех. Метрик стало вдвое больше, Prometheus начинает задыхаться. Артёму нужен другой стек мониторинга.

Разные инструменты подходят для разных задач наблюдаемости.

## Задача

1. Установить open source CMS, включающую nginx, php-fpm и базу данных (MySQL/PostgreSQL)
2. Установить Telegraf для сбора метрик со всех компонентов системы (от VM до БД)
3. Установить InfluxDB, Chronograf, Kapacitor
4. Настроить отправку метрик в InfluxDB
5. Создать сводный дашборд с ключевыми графиками для оценки работоспособности CMS
6. Настроить алерты: чрезмерное потребление ресурсов, падение компонентов CMS, 500-е ошибки

## Базовый стек

Весь стек развёрнут через Docker Compose на одной виртуальной машине (Docker-хосте):

### CMS (WordPress)
- nginx — веб-сервер, отдаёт статику и проксирует PHP в php-fpm
- php-fpm — обработка PHP
- MySQL 8.0 — база данных

### Мониторинг (TICK)
- Telegraf 1.30 — сбор метрик
- InfluxDB 1.8 — хранилище временных рядов
- Chronograf 1.10 — визуализация, дашборды
- Kapacitor 1.7 — обработка данных и алертинг

## Решение ДЗ

Весь стек описан в docker-compose.yml, конфигурация лежит в репозитории и применяется автоматически при запуске: источник данных и дашборд подгружаются в Chronograf, а алерты загружаются в Kapacitor одноразовым контейнером kapacitor-init.

### Структура репозитория

    .
    ├── .gitignore
    ├── .gitattributes
    ├── TICK-1/
    │   ├── docker-compose.yml
    │   ├── .env.example                  # шаблон переменных, .env в git не попадает
    │   ├── nginx/
    │   │   └── nginx.conf                # stub_status, /fpm-status, JSON access-лог
    │   ├── php/
    │   │   └── zz-status.conf            # pm.status_path для php-fpm
    │   ├── mysql/
    │   │   └── init/
    │   │       └── 10-monitoring-user.sh # пользователь для Telegraf
    │   ├── telegraf/
    │   │   └── telegraf.conf
    │   ├── influxdb/
    │   │   └── influxdb.conf
    │   ├── chronograf/
    │   │   └── resources/
    │   │       ├── influxdb.src          # источник InfluxDB
    │   │       ├── kapacitor.kap         # подключение к Kapacitor
    │   │       └── cms-overview.dashboard
    │   ├── kapacitor/
    │   │   ├── kapacitor.conf
    │   │   ├── init.sh                   # define + enable задач
    │   │   ├── tasks/                    # TICKscript-алерты
    │   │   └── handlers/                 # обработчики топика cms
    │   └── scripts/                      # генерация нагрузки для проверки алертов
    └── README.md

### Что собирает Telegraf

| Компонент      | Плагин                                  | Что собираем                                        |
|----------------|-----------------------------------------|-----------------------------------------------------|
| VM / хост      | cpu, mem, swap, disk, diskio, system, processes, kernel | CPU, RAM, диск, I/O, load average    |
| Контейнеры     | docker                                  | CPU, память, сеть по каждому контейнеру             |
| nginx          | nginx (stub_status)                     | Соединения, количество запросов                     |
| nginx (лог)    | tail + JSON                             | Коды ответов, время запроса (nginx_access)          |
| php-fpm        | phpfpm (/fpm-status)                    | Процессы, очередь, max_children_reached             |
| MySQL          | mysql                                   | Потоки, запросы, slow queries, InnoDB               |
| Доступность    | net_response, http_response             | TCP nginx:80, php:9000, mysql:3306; HTTP http://nginx/ |

Данные отправляются в InfluxDB (база telegraf) через outputs.influxdb.

### Chronograf: дашборд CMS Overview

Дашборд состоит из 17 графиков:

| Группа       | Графики                                                            |
|--------------|--------------------------------------------------------------------|
| Хост         | CPU Usage, Memory Usage, Load Average, Disk Usage                  |
| Контейнеры   | CPU, память и сеть по контейнерам                                  |
| nginx        | Соединения, запросы в секунду, ответы по классам 2xx/3xx/4xx/5xx, время ответа (mean/p95/max) |
| php-fpm      | Процессы (active/idle/total), очередь и max_children_reached       |
| MySQL        | Потоки (connected/running), запросы и slow queries в секунду       |
| Доступность  | TCP-проверки компонентов, HTTP-проверка WordPress и время ответа   |

Источник данных, подключение к Kapacitor и сам дашборд подгружаются из chronograf/resources/ автоматически.

### Kapacitor alerting

Алерты описаны на TICKscript в kapacitor/tasks/:

| Алерт                | Тип    | Условие                                          | Уровни                |
|----------------------|--------|--------------------------------------------------|-----------------------|
| cpu_high             | batch  | Среднее использование CPU за 2 минуты            | warn > 70%, crit > 85%|
| mem_high             | batch  | Среднее использование RAM за 2 минуты            | warn > 80%, crit > 90%|
| disk_high            | batch  | Заполнение диска /                               | warn > 80%, crit > 90%|
| component_tcp        | batch  | nginx / php-fpm / mysql не отвечает по TCP       | crit                  |
| component_http       | batch  | WordPress не отдаёт 200                          | crit                  |
| nginx_5xx            | stream | Ответы со статусом >= 500 за минуту              | warn >= 1, crit >= 5  |
| deadman_telegraf     | stream | Метрики хоста не приходят 1 минуту               | crit                  |

Срабатывания пишутся в /var/log/kapacitor/alerts.log и публикуются в топик cms. Опционально можно включить отправку в Telegram (TELEGRAM_ENABLED, TELEGRAM_TOKEN, TELEGRAM_CHAT_ID в .env).

### Запуск

1. Создать .env из шаблона и поменять пароли (порт nginx тоже там):

        cd TICK-1
        cp .env.example .env

2. Запустить стек:

        docker compose up -d
        docker compose ps

   Контейнер kapacitor-init отработает один раз и завершится (Exited 0), это нормально.

3. Открыть http://localhost:8080 и установить WordPress
4. Открыть Chronograf: http://localhost:8888, раздел Dashboards, CMS Overview

Если дашборд не подгрузился автоматически:

        curl -X POST http://localhost:8888/chronograf/v1/dashboards \
          -H 'Content-Type: application/json' \
          --data @chronograf/resources/cms-overview.dashboard

Проверка, что метрики попадают в InfluxDB:

        docker compose exec influxdb influx -database telegraf -execute 'SHOW MEASUREMENTS'

Проверка алертов в Kapacitor:

        docker compose exec kapacitor kapacitor list tasks
        docker compose exec kapacitor tail -f /var/log/kapacitor/alerts.log

### Проверка срабатывания алертов

Перед проверкой нужно установить WordPress и подождать 2–3 минуты, пока накопятся метрики.

| Что проверяем          | Как                                     | Какие алерты сработают                          |
|------------------------|-----------------------------------------|-------------------------------------------------|
| Падение БД и 5xx       | ./scripts/gen-5xx.sh                    | mysql_tcp_down, wordpress_http_down, nginx_5xx  |
| Падение php-fpm        | docker compose stop php                 | php-fpm_tcp_down, nginx_5xx (502)               |
| CPU                    | ./scripts/stress-cpu.sh                 | cpu_high                                        |
| RAM                    | ./scripts/stress-mem.sh                 | mem_high                                        |
| Диск                   | снизить порог в batch_disk_high.tick и выполнить docker compose up kapacitor-init | disk_high |

Восстановление после проверки: docker compose start mysql php. После этого приходят события уровня OK.

Остановка стека:

        docker compose down        # данные сохраняются
        docker compose down -v     # удалить вместе с данными

## Что даёт системе TICK

1. Метрики хоста, CMS и БД собираются одним агентом
2. Дашборд показывает работоспособность CMS одним экраном
3. Алерты ловят перегрузку, падение компонентов и 500-е ошибки
4. Данные в InfluxDB подходят для нагрузки, которая выросла вдвое

## Стек

- Docker, Docker Compose
- Telegraf, InfluxDB, Chronograf, Kapacitor
- WordPress, nginx, PHP-FPM, MySQL
- Telegram Bot API (опционально)
