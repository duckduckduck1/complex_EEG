# Ansible — подготовка сервера и деплой

## Принципы и границы

- Идемпотентность: повторный запуск playbook не ломает настроенный сервер.
- Всё важное (пользователи, директории, пакеты, Docker, конфиги, сервисы)
  описано кодом, а не живёт в памяти администратора.
- Секреты отделены от репозитория.
- Ansible готовит сервер, но не заменяет мониторинг и бэкапы.
- Не входит: бизнес-логика, обработка ЭЭГ, разметка, хранение экспериментов в
  playbook, замена бэкапов/мониторинга, Terraform на текущем этапе.

---

Документ описывает целевую Ansible-реализацию для подготовки и обновления
серверной VM проекта `complex_eeg`.

---

## Владелец

Инфраструктурный слой проекта `complex_eeg`.

Ответственность:

- воспроизводимая подготовка Ubuntu VM;
- установка системных зависимостей;
- настройка пользователей, директорий и прав;
- установка Docker;
- раскладка конфигурации;
- запуск и обновление Docker Compose сервисов;
- подготовка мониторинга и бэкапов.

---

## Назначение

Ansible должен заменить ручную настройку сервера воспроизводимым процессом.

Целевая возможность: взять чистую Ubuntu VM, выполнить playbook и получить
сервер, готовый к запуску второго звена системы.

Ansible не заменяет Docker, CI/CD, мониторинг или бэкапы. Он приводит сервер к
заданному состоянию и запускает нужные сервисы.

---

## Область действия

Входит в документ:

- структура Ansible-кода;
- inventory;
- роли;
- переменные;
- секреты;
- базовые playbook;
- идемпотентность;
- команды запуска;
- проверки после выполнения;
- rollback / recovery.

---

## Вне области

Не входит в документ:

- реализация серверного API;
- реализация Flutter-приложения;
- написание пайплайна обработки;
- Terraform;
- Kubernetes;
- production secrets backend;
- сложная multi-environment release strategy.

---

## Предпосылки

Документ опирается на:

- `linux.md`;
- `docker.md`;
- будущие `backup.md`;
- будущие `monitoring.md`;
- будущий `ci_cd.md`.

Базовые значения:

```text
server_user: deploy
app_group: complex_eeg
project_root: /opt/complex_eeg
app_root: /opt/complex_eeg/app
config_root: /opt/complex_eeg/config
data_root: /srv/complex_eeg
backup_root: /backup/complex_eeg
log_root: /var/log/complex_eeg
monitoring_prometheus_dir: /srv/complex_eeg/monitoring/prometheus
monitoring_grafana_dir: /srv/complex_eeg/monitoring/grafana
backup_status_dir: /backup/complex_eeg/status
restore_test_dir: /backup/complex_eeg/restore_tests
```

---

## Целевое состояние

После внедрения Ansible:

- сервер можно подготовить из чистой Ubuntu VM;
- повторный запуск playbook безопасен;
- пользователи и группы создаются автоматически;
- директории и права создаются автоматически;
- Docker устанавливается автоматически;
- compose-файлы и конфиги раскладываются автоматически;
- сервисы запускаются через `docker compose`;
- бэкапы и мониторинг подготавливаются через роли;
- секреты не хранятся в открытом виде;
- результат выполнения проверяется post-deploy задачами.

---

## Структура Ansible в репозитории

### Решение

Ansible-код размещается в репозитории проекта. Базовый скелет уже создан в:

```text
infra/ansible/
```

Целевая структура:

```text
infra/
  ansible/
    ansible.cfg
    inventories/
      local_vm/
        hosts.yml
        group_vars/
          all.yml
          vault.yml
      production/
        hosts.yml
        group_vars/
          all.yml
          vault.yml
    playbooks/
      bootstrap.yml
      deploy.yml
      backup.yml
      monitoring.yml
    roles/
      base/
      docker/
      app_config/
      deploy/
      backup/
      monitoring/
```

### Правило

Файлы `vault.yml` или их реальные аналоги не должны хранить секреты в открытом
виде. В Git допускаются только зашифрованные секреты или безопасные шаблоны.

---

## ansible.cfg

Минимальный файл уже находится здесь:

```text
infra/ansible/ansible.cfg
```

Содержимое:

```ini
[defaults]
inventory = inventories/local_vm/hosts.yml
remote_user = deploy
roles_path = roles
retry_files_enabled = False
host_key_checking = True
stdout_callback = default

[privilege_escalation]
become = True
become_method = sudo
become_user = root
```

Команды Ansible выполняются из каталога `infra/ansible` либо с явным `-i`.

---

## Inventory

### Решение

Минимально поддерживаются два окружения:

- `local_vm` — текущий стенд разработки и отладки;
- `production` — будущий сервер лаборатории.

### Пример `hosts.yml`

```yaml
all:
  hosts:
    complex_eeg_local:
      ansible_host: 192.0.2.10
      ansible_user: deploy
```

IP-адрес является примером. Реальное значение фиксируется в локальном inventory.

### Проверка подключения

```bash
ansible -i infra/ansible/inventories/local_vm/hosts.yml all -m ping
```

---

## Переменные

### Общие переменные

```yaml
project_name: complex_eeg
server_user: deploy
app_group: complex_eeg

project_root: /opt/complex_eeg
app_root: /opt/complex_eeg/app
config_root: /opt/complex_eeg/config
script_root: /opt/complex_eeg/scripts

data_root: /srv/complex_eeg
experiments_dir: /srv/complex_eeg/experiments
postgres_dir: /srv/complex_eeg/postgres
pipeline_results_dir: /srv/complex_eeg/pipeline_results
upload_tmp_dir: /srv/complex_eeg/upload_tmp

backup_root: /backup/complex_eeg
log_root: /var/log/complex_eeg
```

### Секреты

К секретам относятся:

- `POSTGRES_PASSWORD`;
- `AUTH_SECRET`;
- токены алертов;
- credentials для registry, если появится;
- SSH/private deployment keys, если используются.

Секреты не должны попадать в обычный `group_vars/all.yml`.

### Решение для первого стенда

Используется Ansible Vault.

Реальный файл:

```text
infra/ansible/inventories/local_vm/group_vars/vault.yml
```

Этот файл добавлен в `.gitignore`. В репозитории хранится только безопасный
пример:

```text
infra/ansible/inventories/local_vm/group_vars/vault.example.yml
```

Создание:

```bash
ansible-vault create infra/ansible/inventories/local_vm/group_vars/vault.yml
```

Минимальное содержимое:

```yaml
vault_postgres_password: "replace_me"
vault_auth_secret: "replace_me"
vault_grafana_admin_password: "replace_me"
vault_alertmanager_token: "replace_me"
```

Редактирование:

```bash
ansible-vault edit infra/ansible/inventories/local_vm/group_vars/vault.yml
```

Запуск playbook:

```bash
ansible-playbook -i infra/ansible/inventories/local_vm/hosts.yml \
  infra/ansible/playbooks/bootstrap.yml \
  --ask-vault-pass
```

Для CI/CD без интерактивного ввода можно использовать vault password file, но
сам файл пароля не должен попадать в Git.

---

## Роли

### `base`

Ответственность:

- установка базовых пакетов;
- создание группы `complex_eeg`;
- создание пользователя `deploy`;
- создание директорий;
- настройка прав;
- базовая настройка `ufw`;
- базовая SSH-политика.

### `docker`

Ответственность:

- установка Docker repository;
- установка Docker Engine;
- установка Docker Compose plugin;
- добавление `deploy` в группу `docker`;
- проверка `docker --version`;
- проверка `docker compose version`.

### `app_config`

Ответственность:

- раскладка `.env` или шаблонов конфигурации;
- раскладка compose-файлов;
- раскладка конфигов monitoring/backup;
- проверка, что секреты не пишутся в логи.

### `deploy`

Ответственность:

- получение или обновление кода;
- `docker compose config`;
- `docker compose pull` или `build`;
- `docker compose up -d`;
- post-deploy healthcheck.

### `backup`

Ответственность:

- создание директорий бэкапов;
- раскладка backup scripts;
- настройка расписания;
- настройка логов;
- подготовка status-файла для мониторинга бэкапов.

### `monitoring`

Ответственность:

- раскладка конфигов Prometheus;
- раскладка provisioning для Grafana;
- запуск monitoring-сервисов;
- настройка базовых targets;
- подготовка базовых alert rules.

---

## Playbook

### `bootstrap.yml`

Назначение: первичная подготовка VM.

Содержит роли:

```yaml
- base
- docker
```

### `deploy.yml`

Назначение: обновление приложения и сервисов.

Содержит роли:

```yaml
- app_config
- deploy
```

### `backup.yml`

Назначение: настройка backup jobs.

Содержит роли:

```yaml
- backup
```

### `monitoring.yml`

Назначение: настройка мониторинга.

Содержит роли:

```yaml
- monitoring
```

---

## Команды запуска

Проверка доступности:

```bash
ansible -i infra/ansible/inventories/local_vm/hosts.yml all -m ping
```

Первичная подготовка:

```bash
ansible-playbook -i infra/ansible/inventories/local_vm/hosts.yml \
  infra/ansible/playbooks/bootstrap.yml
```

Деплой:

```bash
ansible-playbook -i infra/ansible/inventories/local_vm/hosts.yml \
  infra/ansible/playbooks/deploy.yml
```

Backup setup:

```bash
ansible-playbook -i infra/ansible/inventories/local_vm/hosts.yml \
  infra/ansible/playbooks/backup.yml
```

Monitoring setup:

```bash
ansible-playbook -i infra/ansible/inventories/local_vm/hosts.yml \
  infra/ansible/playbooks/monitoring.yml
```

---

## Идемпотентность

### Требование

Повторный запуск playbook не должен:

- удалять `/srv/complex_eeg`;
- удалять `/backup/complex_eeg`;
- пересоздавать PostgreSQL data directory;
- менять владельцев данных на неожиданные значения;
- перезапускать сервисы без изменения конфигурации;
- перетирать `.env` без явного решения.

### Проверка

Для ролей нужно использовать check mode там, где это возможно:

```bash
ansible-playbook -i infra/ansible/inventories/local_vm/hosts.yml \
  infra/ansible/playbooks/bootstrap.yml --check --diff
```

---

## Валидация готовности

После выполнения Ansible:

```bash
ansible -i infra/ansible/inventories/local_vm/hosts.yml all -m ping
ssh deploy@SERVER_IP "docker --version"
ssh deploy@SERVER_IP "docker compose version"
ssh deploy@SERVER_IP "test -d /srv/complex_eeg/experiments"
ssh deploy@SERVER_IP "test -d /backup/complex_eeg/postgres"
ssh deploy@SERVER_IP "cd /opt/complex_eeg/app && docker compose ps"
```

Критерии готовности:

- VM доступна по SSH;
- Docker установлен;
- compose-конфигурация валидна;
- сервисы запущены;
- постоянные директории существуют;
- PostgreSQL data не пересоздан;
- healthcheck критичных сервисов успешен.

---

## Rollback / recovery

### Ошибка bootstrap

Действия:

1. Повторить playbook с `--check --diff`.
2. Проверить задачу, на которой произошёл сбой.
3. Исправить роль.
4. Повторить запуск.

Нельзя вручную исправлять сервер так, чтобы изменение не попало обратно в роль.

### Ошибка deploy

Действия:

1. Проверить `docker compose ps`.
2. Проверить логи сервиса.
3. Вернуться к предыдущему образу или commit.
4. Повторить `deploy.yml`.
5. Проверить healthcheck.

### Ошибка с секретами

Действия:

- остановить деплой;
- проверить, не попал ли секрет в логи или Git;
- заменить секрет при подозрении на утечку;
- повторить deploy после исправления secret source.

---

## Передача в CI/CD

CI/CD должен запускать Ansible только после успешных проверок:

- тесты;
- линтеры;
- сборка Docker image;
- `docker compose config`;
- проверка Ansible syntax.

Минимальная проверка Ansible:

```bash
cd infra/ansible
ansible-playbook --syntax-check playbooks/bootstrap.yml
ansible-playbook --syntax-check playbooks/deploy.yml
```

---

## Открытые вопросы

1. Будут ли Docker images собираться на сервере или доставляться из registry.
2. Нужен ли отдельный Ansible user или достаточно `deploy`.
3. Будет ли production inventory храниться в этом же репозитории.
4. Нужна ли отдельная роль reverse proxy.
