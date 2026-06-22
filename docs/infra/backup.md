# Бэкапы и восстановление

## Принципы и границы

- Бэкапим и файлы экспериментов, и PostgreSQL (разные процедуры).
- Исходные эксперименты важнее контейнеров: потерянный `signal.bin` не
  восстановить.
- Бэкапы по расписанию, а не только вручную; восстановление периодически
  проверяется.
- Ошибки бэкапов попадают в мониторинг (тихо сломанный бэкап опаснее явного).
- Не входит: замена основного хранилища, автопочинка повреждённых экспериментов,
  единственная копия на том же диске, ручное копирование как единственный
  механизм.

---

## Статус

Draft.

Документ описывает реализацию резервного копирования для серверного стенда
`complex_eeg`.

---

## Владелец

Инфраструктурный слой проекта `complex_eeg`.

Ответственность:

- бэкап PostgreSQL;
- бэкап файлов экспериментов;
- бэкап результатов обработки;
- хранение backup logs;
- проверка восстановления;
- метрики/статус для мониторинга бэкапов.

---

## Назначение

Бэкапы должны защищать данные экспериментов и серверные метаданные от потери.

Для проекта критичны:

- `signal.bin`;
- `experiment.json`;
- исходные папки экспериментов;
- PostgreSQL metadata/status/history;
- результаты обработки;
- конфигурация, необходимая для восстановления.

Бэкап считается рабочим только после проверки восстановления.

---

## Область действия

Входит в документ:

- что бэкапируется;
- куда складываются бэкапы;
- расписание;
- retention policy;
- команды PostgreSQL dump;
- файловый backup;
- systemd service/timer units;
- статусные файлы для мониторинга;
- проверка восстановления;
- rollback / recovery.

---

## Вне области

Не входит в документ:

- финальный выбор внешнего backup storage;
- шифрование backup archives;
- disaster recovery для облачной инфраструктуры;
- автоматическое исправление повреждённых экспериментов;
- бэкап Docker images как основной механизм восстановления;
- long-term archival policy лаборатории.

---

## Предпосылки

Ожидаемые пути:

```text
data_root: /srv/complex_eeg
experiments_dir: /srv/complex_eeg/experiments
pipeline_results_dir: /srv/complex_eeg/pipeline_results
postgres_dir: /srv/complex_eeg/postgres
backup_root: /backup/complex_eeg
backup_files_dir: /backup/complex_eeg/files
backup_postgres_dir: /backup/complex_eeg/postgres
backup_log_dir: /var/log/complex_eeg/backup
script_root: /opt/complex_eeg/scripts
```

PostgreSQL запускается в Docker Compose как сервис `postgres`.

---

## Целевое состояние

После внедрения backup-слоя:

- PostgreSQL dump выполняется по расписанию;
- файловый backup экспериментов выполняется по расписанию;
- результаты обработки входят в файловый backup или отдельную backup-задачу;
- backup logs пишутся в `/var/log/complex_eeg/backup`;
- последний успешный backup фиксируется в status-файле;
- Prometheus может прочитать статус бэкапа;
- восстановление периодически проверяется;
- backup scripts управляются Ansible.

---

## Backup targets

### PostgreSQL

Бэкапируется:

- карточки экспериментов;
- `experiment_id`;
- метаданные;
- статусы загрузки, валидации и обработки;
- ссылки на файлы;
- ошибки;
- history/status events;
- данные веб-интерфейса.

### Файлы

Бэкапируются:

- `/srv/complex_eeg/experiments`;
- `/srv/complex_eeg/pipeline_results`;
- при необходимости `/srv/complex_eeg/monitoring`;
- конфигурации, которые не восстанавливаются из Git/Ansible.

Не бэкапируются как ценные данные:

- временные загрузки `/srv/complex_eeg/upload_tmp`;
- Docker build cache;
- container writable layers;
- временные файлы.

---

## Backup layout

Целевая структура:

```text
/backup/complex_eeg/
  postgres/
    daily/
    weekly/
    latest/
  files/
    daily/
    weekly/
    latest/
  status/
    postgres_backup.prom
    files_backup.prom
  restore_tests/
```

Создание директорий:

```bash
sudo mkdir -p /backup/complex_eeg/postgres/daily
sudo mkdir -p /backup/complex_eeg/postgres/weekly
sudo mkdir -p /backup/complex_eeg/postgres/latest
sudo mkdir -p /backup/complex_eeg/files/daily
sudo mkdir -p /backup/complex_eeg/files/weekly
sudo mkdir -p /backup/complex_eeg/files/latest
sudo mkdir -p /backup/complex_eeg/status
sudo mkdir -p /backup/complex_eeg/restore_tests
sudo mkdir -p /var/log/complex_eeg/backup
```

---

## Расписание

Initial policy для локальной VM:

```text
PostgreSQL dump: daily
Files backup: daily
Weekly snapshot: weekly
Manual backup: before risky deployments/migrations
```

Retention:

```text
daily: 14 copies
weekly: 8 copies
```

Эти значения являются стартовыми. После оценки реального объёма экспериментов
retention пересматривается.

---

## PostgreSQL backup

### Решение

PostgreSQL бэкапируется через `pg_dump` из контейнера `postgres`.

### Пример команды

```bash
cd /opt/complex_eeg/app

docker compose exec -T postgres \
  pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" \
  | gzip > /backup/complex_eeg/postgres/daily/postgres_$(date -u +%Y%m%dT%H%M%SZ).sql.gz
```

В рабочем скрипте пароль передаётся в контейнер через `PGPASSWORD`, а `pg_dump`
сначала пишет во временный файл. Это нужно, чтобы не зависеть от `trust` в
`pg_hba.conf` и корректно ловить ошибку `pg_dump`.

### Status-файл

После успешного backup обновляется:

```text
/backup/complex_eeg/status/postgres_backup.prom
```

Пример содержимого:

```text
complex_eeg_postgres_backup_success 1
complex_eeg_postgres_backup_last_success_timestamp 1760000000
complex_eeg_postgres_backup_size_bytes 12345678
```

При ошибке:

```text
complex_eeg_postgres_backup_success 0
```

---

## Files backup

### Решение

Для первого стенда выбран `tar.gz` snapshot. Это соответствует структуре
`daily/weekly/latest` и даёт дискретные архивы, которые удобно переносить и
проверять.

`rsync` на первом этапе не используется как основной backup-механизм, чтобы не
смешивать snapshot-подход и mirror-подход.

### Команда

```bash
tar -czf /backup/complex_eeg/files/daily/files_$(date -u +%Y%m%dT%H%M%SZ).tar.gz \
  -C /srv/complex_eeg \
  experiments pipeline_results
```

### Status-файл

```text
/backup/complex_eeg/status/files_backup.prom
```

Пример:

```text
complex_eeg_files_backup_success 1
complex_eeg_files_backup_last_success_timestamp 1760000000
complex_eeg_files_backup_size_bytes 987654321
```

---

## Backup scripts

### Решение

Скрипты располагаются в:

```text
/opt/complex_eeg/scripts/backup/
```

Целевые скрипты:

```text
backup_postgres.sh
backup_files.sh
cleanup_old_backups.sh
restore_check.sh
```

Скелеты уже добавлены в репозиторий:

```text
scripts/backup/backup_postgres.sh
scripts/backup/backup_files.sh
scripts/backup/cleanup_old_backups.sh
scripts/backup/restore_check.sh
```

Скрипты должны:

- завершаться с non-zero exit code при ошибке;
- писать лог в `/var/log/complex_eeg/backup`;
- обновлять status-файлы;
- не выводить секреты в лог;
- не удалять исходные данные.

Скрипты читают `/opt/complex_eeg/config/.env`, если файл существует. При
успешном daily backup в воскресенье UTC создаётся дополнительная weekly-копия.

---

## Scheduling

### Решение

На первом этапе используются systemd timers.

Целевые jobs:

```text
complex-eeg-postgres-backup.timer
complex-eeg-files-backup.timer
complex-eeg-backup-cleanup.timer
complex-eeg-restore-check.timer
```

Скелеты unit-файлов уже добавлены в репозиторий:

```text
infra/systemd/complex-eeg-postgres-backup.service
infra/systemd/complex-eeg-postgres-backup.timer
infra/systemd/complex-eeg-files-backup.service
infra/systemd/complex-eeg-files-backup.timer
infra/systemd/complex-eeg-backup-cleanup.service
infra/systemd/complex-eeg-backup-cleanup.timer
infra/systemd/complex-eeg-restore-check.service
infra/systemd/complex-eeg-restore-check.timer
```

Установка на сервере:

```bash
sudo cp infra/systemd/complex-eeg-*.service /etc/systemd/system/
sudo cp infra/systemd/complex-eeg-*.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now complex-eeg-postgres-backup.timer
sudo systemctl enable --now complex-eeg-files-backup.timer
sudo systemctl enable --now complex-eeg-backup-cleanup.timer
sudo systemctl enable --now complex-eeg-restore-check.timer
```

Проверка:

```bash
systemctl list-timers 'complex-eeg-*'
systemctl status complex-eeg-postgres-backup.timer
```

---

## Restore validation

### PostgreSQL

Проверка выполняется скриптом `restore_check.sh` как реальный restore test:

1. выбрать свежий dump;
2. создать временную PostgreSQL БД в контейнере `postgres`;
3. восстановить dump;
4. завершить restore без ошибки `psql`;
5. удалить временную БД;
6. удалить временную среду.

### Files

Проверка:

1. выбрать свежий файловый backup;
2. восстановить в `/backup/complex_eeg/restore_tests`;
3. проверить, что `tar` архив распаковывается без ошибки;
4. удалить тестовую директорию после проверки.

---

## Валидация готовности

Backup-слой считается готовым, если:

```bash
test -d /backup/complex_eeg/postgres/daily
test -d /backup/complex_eeg/files/daily
test -d /var/log/complex_eeg/backup
test -f /backup/complex_eeg/status/postgres_backup.prom
test -f /backup/complex_eeg/status/files_backup.prom
```

И выполнены проверки:

- PostgreSQL dump создаётся;
- files backup создаётся;
- logs пишутся;
- status-файлы обновляются;
- старые backups удаляются по retention policy;
- восстановление PostgreSQL проверено;
- восстановление файлов проверено.

---

## Rollback / recovery

### Backup job failed

Действия:

1. Проверить лог в `/var/log/complex_eeg/backup`.
2. Проверить место на диске.
3. Проверить доступность PostgreSQL.
4. Проверить права на `/backup/complex_eeg`.
5. Запустить job вручную.
6. Проверить status-файл.

### Restore required

Действия:

1. Остановить сервисы, если они могут писать в повреждённые данные.
2. Выбрать backup.
3. Снять копию текущего повреждённого состояния, если возможно.
4. Восстановить PostgreSQL.
5. Восстановить файлы.
6. Проверить права.
7. Запустить сервисы.
8. Проверить web/API/statuses.

### Accidental backup deletion

Действия:

- проверить, есть ли weekly/external copy;
- остановить cleanup job до выяснения причины;
- восстановить backup из внешнего места, если оно есть;
- пересмотреть retention policy.

---

## Передача в Ansible

В Ansible должны попасть:

- создание backup directories;
- раскладка backup scripts;
- настройка systemd timers;
- настройка прав;
- настройка status-файлов;
- настройка log paths;
- cleanup policy;
- healthcheck backup jobs.

---

## Открытые вопросы

1. Где будет храниться внешняя копия бэкапов.
2. Нужно ли шифровать backup archives на первом стенде.
3. Финальная retention policy после оценки объёма данных.
4. Нужно ли бэкапить Grafana state или всё восстанавливается provisioning.
