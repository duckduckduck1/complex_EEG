# ci_cd.md

## Статус

Draft.

Документ описывает реализацию CI/CD для серверного и инфраструктурного контура
проекта `complex_eeg`.

---

## Владелец

Инфраструктурный слой проекта `complex_eeg`.

Ответственность:

- проверки изменений;
- сборка Docker images;
- проверка compose-конфигурации;
- проверка Ansible;
- управляемый деплой на VM;
- rollback-процедура;
- защита данных при обновлениях.

---

## Назначение

CI/CD должен сделать обновление серверного стенда предсказуемым.

Цель первого этапа: полуавтоматический процесс, где CI выполняет проверки и
сборку, а деплой на VM запускается вручную после осознанного решения.

Автоматический production deploy без ручного подтверждения на текущем этапе не
используется.

---

## Область действия

Входит в документ:

- branch model;
- CI checks;
- Docker image build;
- compose validation;
- Ansible syntax check;
- ShellCheck для shell-скриптов;
- manual deploy;
- rollback;
- migration policy;
- release metadata.

---

## Вне области

Не входит в документ:

- Kubernetes deployment;
- blue-green deployment;
- canary deployment;
- multi-region production;
- автоматический production deploy;
- deployment Flutter-приложения;
- загрузка пользовательских экспериментов.

---

## Предпосылки

Ожидается:

- репозиторий Git уже создан;
- основная ветка: `main`;
- рабочая ветка для разработки: `dev`;
- локальная VM используется как первый серверный стенд;
- Docker Compose описывает сервисы;
- Ansible deploy будет использоваться для обновления VM;
- CI provider — GitHub Actions.

---

## Целевое состояние

CI/CD считается внедрённым, когда:

- pull request или push запускает проверки;
- Markdown/docs checks выполняются без ошибок;
- server/web/pipeline tests запускаются после появления кода;
- Docker images собираются;
- `docker compose config` проходит;
- API image собирается из `server/Dockerfile`;
- Ansible syntax check проходит;
- deploy на VM запускается вручную;
- после deploy выполняется healthcheck;
- rollback описан и проверен.

Скелет workflow уже добавлен:

```text
.github/workflows/ci.yml
```

---

## Branch model

Initial model:

```text
main  - стабильная ветка
dev   - активная разработка
```

Правила:

- `main` должен содержать состояние, которое можно восстановить и развернуть;
- `dev` может содержать текущую разработку;
- deploy на VM выполняется из явно выбранного commit;
- hotfix допускается отдельной веткой при необходимости.

После роста проекта можно перейти на pull request flow.

---

## CI checks

### Documentation

Минимально:

```text
markdown structure check
no trailing whitespace
git diff --check
```

### Server API

После появления кода:

```text
unit tests
integration tests
lint
type check, если применимо
```

### Web

После появления кода:

```text
unit tests
lint
build
static checks
```

### Pipeline

После появления кода:

```text
unit tests
smoke test on small fixture
lint
```

### Infrastructure

```text
docker compose config
shellcheck scripts/backup/*.sh
ansible syntax-check
ansible lint, если используется
```

### GitHub Actions workflow

Минимальный workflow запускается на `push` и `pull_request` в ветки `main` и
`dev`.

Фактический файл:

```text
.github/workflows/ci.yml
```

Workflow использует `.env.example` для `docker compose config`, запускает
ShellCheck для `scripts/backup/*.sh` и выполняет Ansible syntax-check из
каталога `infra/ansible`, чтобы применялся локальный `ansible.cfg`.

---

## Docker image build

### Решение

Docker images должны быть версионируемыми.

Минимальные tags:

```text
commit SHA
branch name for dev builds
latest only for non-critical local usage
```

Пример:

```text
complex-eeg-api:<git_sha>
complex-eeg-web:<git_sha>
complex-eeg-pipeline:<git_sha>
```

`latest` не должен быть единственной ссылкой на версию, развёрнутую на сервере.

---

## Compose validation

Перед deploy:

```bash
docker compose config
```

В CI команда выполняется на compose-файле из репозитория с безопасным
`.env.example`.

Цель:

- проверить синтаксис;
- проверить networks/volumes;
- проверить отсутствующие переменные;
- поймать ошибки до сервера.

---

## Ansible validation

Минимально:

```bash
cd infra/ansible
ansible-playbook --syntax-check playbooks/bootstrap.yml
ansible-playbook --syntax-check playbooks/deploy.yml
ansible-playbook --syntax-check playbooks/backup.yml
ansible-playbook --syntax-check playbooks/monitoring.yml
```

Опционально позже:

```text
ansible-lint
molecule tests
```

---

## Manual deploy flow

### Решение

На первом этапе деплой запускается вручную.

### Процесс

1. Проверить, что CI успешен.
2. Выбрать commit/tag для деплоя.
3. Проверить, затрагивает ли изменение PostgreSQL или формат данных.
4. Если затрагивает — выполнить дополнительный backup.
5. Запустить Ansible deploy.
6. Проверить healthcheck.
7. Проверить web/API.
8. Проверить логи.
9. Зафиксировать deployed version.

### Команда

```bash
ansible-playbook -i infra/ansible/inventories/local_vm/hosts.yml \
  infra/ansible/playbooks/deploy.yml \
  --extra-vars "deploy_version=<git_sha>"
```

---

## Healthcheck after deploy

Минимальные проверки:

```bash
ssh deploy@SERVER_IP "cd /opt/complex_eeg/app && docker compose ps"
curl -f http://SERVER_IP/health
curl -f http://SERVER_IP/ready
```

`/ready` может вернуть `503`, если PostgreSQL или runtime-директории ещё не
подготовлены. В этом случае деплой считается незавершённым, а причина берётся из
JSON-поля `checks`.

После появления web:

```bash
curl -f http://SERVER_IP/
```

После появления Prometheus:

```bash
curl -f http://SERVER_IP:9090/-/ready
```

Для production-доступа конкретные endpoints будут уточнены после reverse proxy.

---

## Rollback

### Условия rollback

Rollback нужен, если:

- API не стартует;
- web не отвечает;
- pipeline не запускается;
- healthcheck failed;
- загрузка экспериментов сломалась;
- новая версия пишет некорректные статусы;
- миграция БД завершилась ошибкой.

### Процедура без миграций БД

1. Выбрать предыдущий working commit/image tag.
2. Запустить deploy с предыдущей версией.
3. Проверить `docker compose ps`.
4. Проверить healthcheck.
5. Проверить web/API.
6. Зафиксировать причину rollback.

### Процедура с миграциями БД

Если релиз менял схему БД:

- rollback контейнеров может быть недостаточен;
- перед deploy должен быть backup;
- восстановление БД выполняется только по процедуре `backup.md`;
- manual approval обязателен.

---

## Migration policy

### Решение

Миграции PostgreSQL должны быть версионированными и применяться контролируемо.

Требования:

- миграции хранятся в Git;
- миграции проходят CI checks;
- перед risky migration выполняется backup;
- downgrade strategy фиксируется, если возможна;
- manual DB changes на сервере запрещены.

До появления server-кода конкретный инструмент миграций не выбирается.

---

## Release metadata

На сервере должна быть доступна информация:

```text
deployed_commit
deployed_at
deployed_by
image_tags
migration_version
```

Возможные места хранения:

- файл в `/opt/complex_eeg/app`;
- запись в PostgreSQL;
- label Docker image;
- annotation в monitoring dashboard.

Финальное решение принимается при реализации deploy pipeline.

---

## Валидация готовности

CI/CD слой считается готовым, если:

- `git diff --check` выполняется в CI;
- `docker compose config` выполняется в CI;
- ShellCheck выполняется для `scripts/backup/*.sh`;
- Ansible syntax check выполняется в CI;
- Docker images собираются;
- manual deploy на VM работает;
- healthcheck после deploy работает;
- rollback на предыдущую версию проверен хотя бы один раз.

---

## Передача в Ansible

Ansible является механизмом деплоя.

CI/CD передаёт в Ansible:

- выбранную версию;
- registry/image tags;
- окружение;
- флаг необходимости миграций, если будет реализован;
- deploy metadata.

Ansible не должен сам выбирать случайную последнюю версию.

---

## Открытые вопросы

1. Где хранить Docker images: GitHub Container Registry, Docker Hub или локально.
2. Нужны ли PR checks уже на первом этапе.
3. Какой инструмент миграций будет у server API.
4. Где хранить deploy metadata.
5. Когда переходить от ручного deploy к автоматизированному deploy по approval.
