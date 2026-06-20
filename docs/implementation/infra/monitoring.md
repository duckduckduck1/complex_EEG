# monitoring.md

## Статус

Draft.

Документ описывает реализацию мониторинга для серверного стенда `complex_eeg`.

---

## Владелец

Инфраструктурный слой проекта `complex_eeg`.

Ответственность:

- сбор системных и сервисных метрик;
- Grafana dashboards;
- alert rules;
- мониторинг API, PostgreSQL, Docker, пайплайна и бэкапов;
- базовая диагностика состояния серверного звена.

---

## Назначение

Мониторинг должен отвечать на вопрос: работает ли серверная система и где
произошёл сбой, если она не работает.

Мониторинг не исправляет ошибки автоматически. Он делает сбои видимыми и даёт
данные для runbook.

---

## Область действия

Входит в документ:

- Prometheus;
- Grafana;
- exporters;
- метрики;
- alert rules;
- dashboards;
- backup status metrics;
- проверка готовности;
- rollback / recovery.

---

## Вне области

Не входит в документ:

- реализация бизнес-метрик server API;
- централизованный лог-стек;
- внешний alert delivery provider;
- SLO/SLA production-уровня;
- автоматическое исправление инцидентов;
- ML/MLOps monitoring.

---

## Предпосылки

Ожидается, что выполнены:

- `linux.md`;
- `docker.md`;
- частично `backup.md` для status-файлов бэкапов.

Мониторинг запускается через Docker Compose.

Ожидаемые директории:

```text
/srv/complex_eeg/monitoring
/var/log/complex_eeg
/backup/complex_eeg/status
```

---

## Целевое состояние

После внедрения monitoring-слоя:

- Prometheus запущен;
- Grafana запущена;
- системные метрики VM собираются;
- Docker/container metrics доступны;
- PostgreSQL metrics доступны;
- API/web healthcheck видны;
- backup status metrics доступны;
- есть базовые dashboards;
- есть базовые alert rules;
- мониторинг не требует доступа к исходным данным экспериментов.

---

## Сервисы

Целевой состав:

```text
prometheus
grafana
node-exporter
cadvisor
postgres-exporter
```

Опционально позже:

```text
blackbox-exporter
alertmanager
```

### Ответственность

- `prometheus` — сбор и хранение метрик;
- `grafana` — визуализация;
- `node-exporter` — CPU/RAM/disk/network VM;
- `node-exporter` с textfile collector — чтение `.prom` файлов бэкапов;
- `cadvisor` — контейнерные метрики;
- `postgres-exporter` — PostgreSQL metrics;
- `blackbox-exporter` — внешняя проверка HTTP endpoints;
- `alertmanager` — маршрутизация алертов.

---

## Сетевой доступ

### Решение

Prometheus и Grafana не должны быть публично открыты без ограничения доступа.

Initial local VM policy:

- Grafana доступна только из доверенной сети/VPN/SSH tunnel;
- Prometheus не публикуется наружу;
- exporters доступны только внутри Docker/internal network или localhost.

### Открытые порты

Типовые порты:

```text
grafana: 3000
prometheus: 9090
node-exporter: 9100
cadvisor: 8080
postgres-exporter: 9187
```

Публикация наружу определяется в `docker-compose.yml` и firewall.

---

## Prometheus configuration

### Расположение

```text
/opt/complex_eeg/config/prometheus/prometheus.yml
/opt/complex_eeg/config/prometheus/alerts.yml
```

### Targets

Минимальные scrape jobs:

```yaml
scrape_configs:
  - job_name: node
    static_configs:
      - targets: ["node-exporter:9100"]

  - job_name: containers
    static_configs:
      - targets: ["cadvisor:8080"]

  - job_name: postgres
    static_configs:
      - targets: ["postgres-exporter:9187"]

  - job_name: api
    metrics_path: /metrics
    static_configs:
      - targets: ["api:8000"]
```

API metrics endpoint появится после реализации server API. До этого для API
достаточно healthcheck.

---

## Backup metrics

### Решение

Backup scripts пишут Prometheus textfile metrics:

```text
/backup/complex_eeg/status/postgres_backup.prom
/backup/complex_eeg/status/files_backup.prom
```

Эти файлы должны быть доступны Prometheus через node-exporter textfile collector.

Для первого стенда используется флаг:

```text
--collector.textfile.directory=/backup_status
```

В `docker-compose.yml` это смонтировано так:

```text
/backup/complex_eeg/status -> /backup_status:ro
```

Минимальные метрики:

```text
complex_eeg_postgres_backup_success
complex_eeg_postgres_backup_last_success_timestamp
complex_eeg_postgres_backup_size_bytes

complex_eeg_files_backup_success
complex_eeg_files_backup_last_success_timestamp
complex_eeg_files_backup_size_bytes
```

---

## Метрики

### System

- CPU usage;
- RAM usage;
- disk usage;
- filesystem available bytes;
- network;
- uptime;
- system load.

### Docker

- container running/stopped;
- restart count;
- CPU per container;
- memory per container;
- container logs growth, если будет доступно.

### PostgreSQL

- availability;
- active connections;
- database size;
- transaction/errors;
- replication не требуется на текущем этапе.

### Application

- API health;
- structured request logs with request_id;
- upload sessions count;
- upload errors;
- validation failures;
- processing queue length;
- processing failures;
- request latency, если реализуется.

### Backups

- last successful PostgreSQL backup timestamp;
- last successful files backup timestamp;
- backup success flag;
- backup size;
- backup age.

---

## Dashboards

### `System Overview`

Панели:

- CPU;
- RAM;
- disk usage;
- filesystem free;
- uptime;
- network;
- Docker containers status.

### `Application Overview`

Панели:

- API health;
- web health;
- upload count;
- validation failures;
- processing statuses;
- processing failures.

### `PostgreSQL`

Панели:

- PostgreSQL up/down;
- DB size;
- connections;
- errors;
- disk usage for `/srv/complex_eeg/postgres`.

### `Backups`

Панели:

- last PostgreSQL backup time;
- last files backup time;
- backup success flags;
- backup sizes;
- backup age.

---

## Alerts

### Critical

- API down;
- PostgreSQL down;
- disk usage above critical threshold;
- filesystem read-only;
- backup stale;
- backup failed;
- container restart loop;
- pipeline failures above threshold.

В первом стенде `alerts.yml` уже содержит базовые правила для API, PostgreSQL,
disk 80/90%, stale backup больше 36 часов, failed backup и container restart
loop. Доставка уведомлений через Alertmanager пока помечена как pending:
конфигурационный блок `alerting` оставлен закомментированным в `prometheus.yml`.

### Warning

- disk usage above warning threshold;
- processing queue growing;
- validation failures increasing;
- high memory usage;
- backup size unexpectedly zero.

### Initial thresholds

```text
disk_warning: > 80%
disk_critical: > 90%
backup_stale: > 36h for daily backup
container_restarts_warning: > 3 in 15m
```

Пороговые значения пересматриваются после первых реальных запусков.

---

## Логи

Monitoring-слой не заменяет логи.

Минимальные источники логов:

```bash
docker compose logs api
docker compose logs web
docker compose logs postgres
docker compose logs pipeline-worker
docker compose logs prometheus
docker compose logs grafana
journalctl -u docker
```

Централизованный лог-стек не входит в первый этап. Если локального просмотра
логов станет недостаточно, добавляется отдельное решение.

---

## Валидация готовности

Проверки:

```bash
cd /opt/complex_eeg/app
docker compose ps prometheus grafana
curl -f http://localhost:9090/-/ready
curl -f http://localhost:3000/api/health
```

Критерии готовности:

- Prometheus ready;
- Grafana отвечает;
- node-exporter target up;
- PostgreSQL exporter target up;
- API health target добавлен или явно помечен как pending;
- backup metrics files читаются;
- node-exporter запущен с `--collector.textfile.directory`;
- dashboards доступны;
- alert rules загружаются без ошибок.

---

## Rollback / recovery

### Prometheus не стартует

Действия:

1. Проверить `docker compose logs prometheus`.
2. Проверить `prometheus.yml`.
3. Запустить `promtool check config`, если доступен.
4. Вернуть предыдущую конфигурацию.
5. Перезапустить Prometheus.

### Grafana не стартует

Действия:

1. Проверить `docker compose logs grafana`.
2. Проверить volume/data directory.
3. Проверить provisioning-конфиги.
4. Перезапустить Grafana.

### Alerts шумят

Действия:

- проверить реальность проблемы;
- уточнить threshold;
- не отключать alert без фиксации причины;
- обновить runbook, если alert валиден.

---

## Передача в Ansible

В Ansible должны попасть:

- директории monitoring config;
- Prometheus config;
- alert rules;
- Grafana provisioning;
- compose-сервисы monitoring;
- healthcheck после запуска;
- базовые dashboards, если они хранятся как JSON.

---

## Открытые вопросы

1. Будет ли использоваться Alertmanager на первом этапе.
2. Куда отправлять алерты: email, Telegram, локально в Grafana.
3. Нужен ли central logging stack.
4. Как ограничить доступ к Grafana на локальной VM.
5. Будет ли API сразу отдавать `/metrics` или только `/health`.
