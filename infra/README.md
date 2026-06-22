# Инфраструктура (код)

Здесь лежит сама инфраструктурная конфигурация проекта — **не документация**.
Дизайн, принципы и обоснование — в [docs/infra/](../docs/infra/README.md).

## Состав

- `ansible/` — повторяемая подготовка сервера и деплой:
  - `playbooks/` — `bootstrap`, `deploy`, `backup`, `monitoring`;
  - `roles/` — `base`, `docker`, `app_config`, `deploy`, `backup`, `monitoring`;
  - `inventories/local_vm/` — инвентарь и переменные (секреты — через vault,
    см. `vault.example.yml`);
  - `ansible.cfg`.
- `nginx/nginx.conf` — конфиг веб-входа (монтируется в контейнер `web`).
- `monitoring/prometheus/` — `prometheus.yml` и `alerts.yml` (монтируются в
  контейнер `prometheus`).
- `systemd/` — таймеры и сервисы бэкапов и проверки восстановления
  (`*-files-backup`, `*-postgres-backup`, `*-backup-cleanup`, `*-restore-check`).

## Как используется

- `docker-compose.yml` монтирует `nginx/nginx.conf` и `monitoring/prometheus/*`
  напрямую в соответствующие контейнеры.
- `ansible/` готовит сервер и разворачивает стек — см.
  [docs/infra/ansible.md](../docs/infra/ansible.md) и
  [docs/infra/ci_cd.md](../docs/infra/ci_cd.md).
- `systemd/` запускает бэкапы по расписанию — см.
  [docs/infra/backup.md](../docs/infra/backup.md) и
  [docs/infra/runbook.md](../docs/infra/runbook.md).
