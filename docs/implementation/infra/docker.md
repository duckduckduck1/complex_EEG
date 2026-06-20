# docker.md

## Статус

Draft.

Документ описывает целевую Docker-реализацию серверного стенда `complex_eeg`.
Он опирается на Linux-пути и пользователей из `linux.md`.

---

## Владелец

Инфраструктурный слой проекта `complex_eeg`.

Ответственность:

- установка Docker Engine и Docker Compose plugin;
- описание контейнерного состава серверного стенда;
- разделение сервисов, сетей и постоянных данных;
- правила обновления и отката контейнеров;
- базовые проверки готовности Docker-слоя.

---

## Назначение

Docker-слой должен обеспечить воспроизводимый запуск серверного звена на Ubuntu
VM: API, веб-интерфейс, PostgreSQL, валидация, пайплайн обработки, мониторинг и
служебные задачи.

Контейнеры являются исполняемой средой. Данные экспериментов, PostgreSQL,
результаты обработки, логи и бэкапы хранятся вне контейнеров.

---

## Область действия

Входит в документ:

- установка Docker Engine;
- установка Docker Compose plugin;
- добавление пользователя `deploy` в группу `docker`;
- целевой состав compose-сервисов;
- сети Docker;
- bind mounts и volume;
- переменные окружения;
- healthcheck;
- базовые команды управления;
- проверки готовности;
- rollback / recovery.

---

## Вне области

Не входит в документ:

- реализация server API;
- реализация web UI;
- реализация pipeline-кода;
- схема PostgreSQL;
- Ansible playbook;
- CI/CD pipeline;
- Prometheus/Grafana dashboards;
- backup scripts;
- Kubernetes.

---

## Предпосылки

Должен быть выполнен `linux.md`.

Ожидаемые пути:

```text
project_root: /opt/complex_eeg
app_root: /opt/complex_eeg/app
config_root: /opt/complex_eeg/config
script_root: /opt/complex_eeg/scripts
data_root: /srv/complex_eeg
backup_root: /backup/complex_eeg
log_root: /var/log/complex_eeg
```

Ожидаемые пользователь и группа:

```text
server_user: deploy
app_group: complex_eeg
```

---

## Целевое состояние

После выполнения Docker-слоя:

- Docker Engine установлен;
- Docker Compose plugin установлен;
- пользователь `deploy` может управлять Docker;
- compose-файл расположен в `/opt/complex_eeg/app`;
- сервисы запускаются через `docker compose`;
- PostgreSQL не опубликован наружу;
- API/web публикуются только через явно заданные порты;
- постоянные данные находятся в `/srv/complex_eeg`;
- логи приложения находятся в `/var/log/complex_eeg`;
- прикладные контейнеры пишут в bind mounts с UID/GID, совместимыми с
  `deploy:complex_eeg`;
- контейнеры можно пересоздать без потери экспериментов;
- базовые healthcheck доступны.

---

## Установка Docker

### Решение

Используется официальный Docker Engine и Docker Compose plugin. Docker Desktop на
сервере не используется.

### Процедура

```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

### Проверка

```bash
docker --version
docker compose version
sudo systemctl status docker
```

---

## Доступ пользователя deploy к Docker

### Решение

Пользователь `deploy` управляет контейнерами без постоянной работы из-под `root`.

### Процедура

```bash
sudo usermod -aG docker deploy
```

После этого нужно перелогиниться:

```bash
exit
ssh deploy@SERVER_IP
```

### Проверка

```bash
groups
docker ps
docker run --rm hello-world
```

### Риск

Участие в группе `docker` фактически даёт высокий уровень доступа к хосту.
Доступ к пользователю `deploy` должен быть защищён SSH-ключами и ограничен.

---

## Compose layout

### Решение

Основной compose-файл хранится в репозитории и разворачивается из:

```text
/opt/complex_eeg/app/docker-compose.yml
```

В репозитории уже есть скелет:

```text
docker-compose.yml
```

Файл окружения для серверной VM:

```text
/opt/complex_eeg/config/.env
```

`.env` не хранится в Git. В репозитории допустим только шаблон:

```text
.env.example
```

### Базовая структура

```text
/opt/complex_eeg/app/
  docker-compose.yml
  .env.example

/opt/complex_eeg/config/
  .env
```

### Правило

Compose-файл описывает сервисы и mounts. Секреты и machine-specific значения
передаются через `.env`, Ansible secrets или другой утверждённый механизм.

---

## Сервисы

### Целевой состав

```text
api
web
postgres
validator
pipeline-worker
prometheus
grafana
```

### Ответственность сервисов

- `api` — приём экспериментов, загрузочные сессии, статусы, API для приложения и
  web;
- `web` — веб-интерфейс для коллег;
- `postgres` — PostgreSQL;
- `validator` — проверка пакетов экспериментов, если выделяется отдельным
  сервисом;
- `pipeline-worker` — обработка принятых экспериментов;
- `prometheus` — сбор метрик;
- `grafana` — дашборды.

Backup jobs на первом стенде запускаются на хосте через systemd timers. В
`docker-compose.yml` отдельный `backup`-контейнер не используется.

### Открытый вопрос

`validator` может быть:

- отдельным контейнером;
- частью `api`;
- фоновой задачей внутри server-приложения.

Решение принимается при реализации server/API.

---

## API Runtime

### Текущее решение

`api` больше не является placeholder-контейнером. Он собирается из:

```text
server/Dockerfile
```

Compose-фрагмент:

```yaml
api:
  build:
    context: ./server
    dockerfile: Dockerfile
  image: ${API_IMAGE:-complex-eeg-api:local}
  command:
    - python
    - -m
    - uvicorn
    - app.main:app
    - --host
    - 0.0.0.0
    - --port
    - "8000"
```

Dockerfile устанавливает server package через:

```bash
python -m pip install .
```

Это означает, что внутри контейнера доступны:

- FastAPI-приложение `app.main:app`;
- CLI `complex-eeg`;
- зависимости из `server/pyproject.toml`.

### Важное ограничение

API-контейнер может стартовать и отвечать на `/health` до применения Alembic
migrations, потому что `/health` проверяет только живость процесса.

Операции, которые обращаются к PostgreSQL-таблицам (`login`, upload sessions,
создание пользователя через CLI), требуют, чтобы миграции уже создали таблицы.
До появления migration files это проверяется вручную и считается зоной DB
handoff.

---

## Модель прав bind mount

### Решение

На первом стенде прикладные контейнеры (`api`, `validator`, `pipeline-worker`)
запускаются не от root, а с UID/GID из переменных:

```text
APP_UID
APP_GID
```

На VM значения должны соответствовать:

```bash
id -u deploy
getent group complex_eeg | cut -d: -f3
```

Host-директории `/srv/complex_eeg`, `/backup/complex_eeg` и
`/var/log/complex_eeg` имеют group-write и setgid bit. Это позволяет контейнерам
писать в bind mounts без `chmod 777`.

PostgreSQL-контейнер использует официальный entrypoint образа и управляет правами
своей data directory внутри `/srv/complex_eeg/postgres`. Эту директорию нельзя
исправлять вручную без процедуры восстановления.

### Проверка

```bash
id -u deploy
getent group complex_eeg
ls -ld /srv/complex_eeg /backup/complex_eeg /var/log/complex_eeg
docker compose exec api sh -c "touch /srv/complex_eeg/upload_tmp/permission_check && rm /srv/complex_eeg/upload_tmp/permission_check"
```

---

## Сети

### Решение

Используются отдельные Docker-сети для публичного входа и внутренних сервисов.

Целевая модель:

```text
public_net
  api
  web

internal_net
  api
  postgres
  validator
  pipeline-worker
  prometheus

monitoring_net
  prometheus
  grafana
  exporters
```

### Правила

- PostgreSQL не публикуется на хостовый порт.
- `api` доступен через HTTP/HTTPS endpoint.
- `web` доступен через HTTP/HTTPS endpoint.
- `pipeline-worker` не доступен снаружи.
- `prometheus` и `grafana` доступны только по выбранной политике доступа.

---

## Постоянные данные

### Решение

Для ценных данных используются bind mounts на хостовые директории из `linux.md`.

Целевая схема:

```text
/srv/complex_eeg/postgres          -> postgres data
/srv/complex_eeg/experiments       -> исходные эксперименты
/srv/complex_eeg/pipeline_results  -> результаты обработки
/srv/complex_eeg/upload_tmp        -> временные загрузки
/srv/complex_eeg/monitoring        -> данные мониторинга, если нужны
/var/log/complex_eeg               -> прикладные логи
/backup/complex_eeg                -> бэкапы
```

### Запрещено

- хранить единственную копию экспериментов внутри writable layer контейнера;
- хранить PostgreSQL data внутри одноразового контейнера без volume/bind mount;
- хранить бэкапы внутри контейнера;
- удалять `/srv/complex_eeg` при пересоздании контейнеров.

---

## Переменные окружения

### Решение

Runtime-конфигурация передаётся через `.env` или секреты Ansible.

Минимальные группы переменных:

```text
APP_ENV
APP_BASE_URL
API_PORT
WEB_PORT
DATA_ROOT

POSTGRES_DB
POSTGRES_USER
POSTGRES_PASSWORD
POSTGRES_HOST
POSTGRES_PORT

EXPERIMENTS_DIR
PIPELINE_RESULTS_DIR
UPLOAD_TMP_DIR
BACKUP_DIR
BACKUP_STATUS_DIR
LOG_DIR
LOG_LEVEL
REQUEST_ID_HEADER

AUTH_SECRET
SESSION_COOKIE_NAME
SESSION_TTL_HOURS
SESSION_COOKIE_SECURE
GF_SECURITY_ADMIN_USER
GF_SECURITY_ADMIN_PASSWORD
ALERTMANAGER_TOKEN
UPLOAD_MAX_SIZE
UPLOAD_SESSION_TTL_HOURS
```

### Правила

- `.env` не коммитится;
- `.env.example` содержит только безопасные примеры;
- production-секреты не попадают в Docker image;
- при смене секретов фиксируется процедура обновления.

---

## Образы

### Решение

На сервере не используется `latest` как единственная ссылка на версию.
Production-like deploy должен использовать image tag по `git_sha` или явной
версии.

Допустимо:

```text
complex-eeg-api:<git_sha>
complex-eeg-web:<git_sha>
complex-eeg-pipeline:<git_sha>
```

`latest` допустим только для локальной отладки и не должен быть единственным
способом понять, какая версия развёрнута на сервере.

### Проверка

```bash
docker compose images
```

---

## Healthcheck

### Решение

Каждый критичный сервис должен иметь проверку готовности.

Минимально:

- `api` — HTTP health endpoint;
- `web` — HTTP response;
- `postgres` — `pg_isready`;
- `pipeline-worker` — проверка процесса/очереди;
- `prometheus` — HTTP endpoint;
- `grafana` — HTTP endpoint.

Статус backup jobs проверяется через `.prom` файлы и node-exporter textfile
collector, а не через compose-сервис.

### Проверки

```bash
docker compose ps
docker compose logs api
docker compose logs postgres
```

После реализации API:

```bash
curl -f http://localhost:${API_PORT:-8000}/health
curl -f http://localhost:${API_PORT:-8000}/ready
```

`/ready` проверяет PostgreSQL connection и runtime-директории. Он может вернуть
`503`, если PostgreSQL ещё не доступен или bind mounts не подготовлены.

Compose healthcheck для `api` использует `/health`, чтобы проверять именно запуск
FastAPI-процесса. Это позволяет отдельно диагностировать ситуацию: контейнер
жив, но runtime dependency ещё не готова.

---

## Базовые команды управления

Выполняются из:

```bash
cd /opt/complex_eeg/app
```

Команды:

```bash
docker compose config
docker compose pull
docker compose build
docker compose up -d
docker compose ps
docker compose logs -f
docker compose down
```

Для остановки без удаления данных:

```bash
docker compose down
```

Нельзя использовать команды, удаляющие volume или host directories, без явного
понимания последствий.

---

## Обновление сервисов

### Целевой процесс

1. Проверить наличие свежего бэкапа, если обновление затрагивает PostgreSQL,
   формат данных или pipeline results.
2. Получить новую версию кода или образов.
3. Проверить compose-конфигурацию.
4. Запустить обновление контейнеров.
5. Проверить healthcheck.
6. Проверить, что данные доступны.
7. Зафиксировать результат.

### Команды

```bash
cd /opt/complex_eeg/app
docker compose config
docker compose pull
docker compose up -d
docker compose ps
```

Если образы собираются на сервере:

```bash
docker compose build api
docker compose up -d
```

---

## Валидация готовности

Docker-слой считается готовым, если:

```bash
docker --version
docker compose version
docker ps
docker compose config
docker compose ps
```

Критерии готовности:

- Docker daemon работает;
- пользователь `deploy` может выполнять `docker ps`;
- compose-файл валиден;
- сервисы запускаются;
- PostgreSQL не опубликован наружу;
- постоянные данные подключены через bind mounts/volume;
- пересоздание контейнера не удаляет данные;
- логи доступны через `docker compose logs`.

---

## Rollback / recovery

### Неудачное обновление контейнера

Действия:

1. Проверить `docker compose ps`.
2. Проверить `docker compose logs SERVICE`.
3. Вернуться к предыдущему образу или предыдущему commit.
4. Запустить `docker compose up -d`.
5. Проверить healthcheck.

### Повреждён compose-файл

Действия:

```bash
docker compose config
git checkout -- docker-compose.yml
```

Если файл уже изменён в рабочем дереве руками, сначала сохранить копию для
анализа.

### Ошибка с PostgreSQL volume

Нельзя:

- выполнять `docker compose down -v`;
- удалять `/srv/complex_eeg/postgres`;
- пересоздавать PostgreSQL data directory без решения о восстановлении.

Действия:

- остановить зависимые сервисы;
- проверить логи PostgreSQL;
- проверить права на `/srv/complex_eeg/postgres`;
- проверить свободное место;
- перейти к процедуре восстановления из `backup.md`, если данные повреждены.

### Нехватка места из-за Docker

Проверки:

```bash
docker system df
df -h
```

Очистка Docker cache допускается только после проверки, что удаляются не данные:

```bash
docker image prune
docker builder prune
```

Не использовать агрессивные prune-команды без понимания, какие volume и сети
будут затронуты.

---

## Передача в Ansible

В Ansible должны быть перенесены:

- установка Docker repository;
- установка Docker Engine и Compose plugin;
- добавление `deploy` в группу `docker`;
- раскладка compose-файлов;
- раскладка `.env` или шаблонов конфигурации;
- создание Docker-сетей, если они не создаются compose автоматически;
- запуск `docker compose up -d`;
- healthcheck после деплоя.

Целевое свойство: повторный запуск Ansible не удаляет Docker data, PostgreSQL
data, эксперименты, результаты обработки и бэкапы.

---

## Открытые вопросы

1. Будет ли `validator` отдельным контейнером или частью `api`.
2. Будет ли API/web закрыт reverse proxy на этом этапе.
3. Нужно ли ограничивать ресурсы контейнеров на первой VM.
4. Какой registry будет использоваться для Docker images.
