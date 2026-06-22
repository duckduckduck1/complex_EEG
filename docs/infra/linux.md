# Linux-среда сервера

Документ описывает целевую Linux-подготовку серверной VM для первого
реализационного стенда. После ручной проверки эти шаги должны быть перенесены в
Ansible.

---

## Владелец

Инфраструктурный слой проекта `complex_eeg`.

Ответственность:

- подготовка Ubuntu VM;
- базовая безопасность доступа;
- файловая структура для данных и сервисов;
- системные предпосылки для Docker, Ansible, мониторинга и бэкапов.

---

## Назначение

Подготовить серверную Linux-среду, на которой будет развёрнуто второе
функциональное звено системы: API, валидация, PostgreSQL, файловое хранилище,
пайплайн обработки, веб-интерфейс, мониторинг и бэкапы.

Linux-слой не реализует бизнес-логику приложения. Его задача — предоставить
предсказуемую и воспроизводимую операционную основу.

---

## Область действия

Входит в документ:

- базовые предпосылки Ubuntu VM;
- системные пользователи и группы;
- SSH-доступ;
- базовые пакеты;
- файловая структура;
- права доступа;
- firewall;
- проверка времени и диска;
- Linux-level проверки готовности;
- требования для последующего переноса в Ansible.

---

## Вне области

Не входит в документ:

- установка Docker;
- Docker Compose;
- PostgreSQL configuration;
- серверный API;
- веб-интерфейс;
- пайплайн обработки;
- Prometheus/Grafana;
- бэкапы;
- CI/CD;
- Ansible playbook;
- production hardening сверх базового SSH/firewall.

---

## Предпосылки

Исходные условия:

- используется одна Ubuntu VM;
- доступ к VM выполняется по SSH;
- серверная часть будет запускаться в Docker-контейнерах;
- данные должны храниться вне контейнеров;
- Kubernetes и Terraform на текущем этапе не используются;
- сервер не участвует в live-записи ЭЭГ.

Рабочие имена:

```text
project_name: complex_eeg
server_user: deploy
app_group: complex_eeg
project_root: /opt/complex_eeg
data_root: /srv/complex_eeg
backup_root: /backup/complex_eeg
log_root: /var/log/complex_eeg
```

Эти значения являются базовым контрактом для следующих документов:

- `docker.md`;
- `ansible.md`;
- `ci_cd.md`;
- `monitoring.md`;
- `backup.md`;
- `runbook.md`.

---

## Целевое состояние

После выполнения документа сервер должен находиться в следующем состоянии:

- VM доступна по SSH;
- создан пользователь `deploy`;
- создана группа `complex_eeg`;
- установлены базовые системные пакеты;
- создана файловая структура проекта;
- данные, бэкапы, логи и код разделены по директориям;
- PostgreSQL и файлы экспериментов не предполагается хранить внутри контейнера;
- firewall закрывает входящие соединения по умолчанию;
- SSH разрешён;
- HTTP/HTTPS зарезервированы для будущего API/web;
- PostgreSQL не открыт наружу;
- директории, в которые пишут контейнеры, доступны UID/GID контейнеров;
- системное время корректно;
- достаточно места под первые данные и бэкапы.

---

## Системные пользователи

### Решение

Приложение не должно обслуживаться из-под `root`.

Используются:

- `root` — только для административных операций;
- `deploy` — пользователь для деплоя и обслуживания проекта;
- `complex_eeg` — группа владельцев проектных директорий.

На первом стенде `deploy` получает полный `sudo`. Это временное решение для
быстрой отладки. После переноса в Ansible доступ должен быть ограничен
необходимыми эксплуатационными командами.

### Процедура

```bash
sudo groupadd --system complex_eeg
sudo useradd --create-home --shell /bin/bash --groups complex_eeg deploy
sudo usermod -aG sudo deploy
```

Доступ пользователя `deploy` к Docker настраивается позже в `docker.md`, после
установки Docker.

### Проверка

```bash
id deploy
getent group complex_eeg
```

Ожидаемый результат:

- пользователь `deploy` существует;
- группа `complex_eeg` существует;
- пользователь `deploy` входит в группу `complex_eeg`;
- пользователь `deploy` имеет административные права через `sudo`.

---

## SSH-доступ

### Решение

SSH является основным способом администрирования VM.

Требования:

- доступ только для разрешённых пользователей;
- предпочтительный способ входа — SSH key;
- root-login должен быть отключён после проверки доступа `deploy`;
- password authentication может быть отключена после проверки ключевого доступа.

### Процедура проверки доступа

Создать каталог ключей:

```bash
sudo mkdir -p /home/deploy/.ssh
sudo chmod 700 /home/deploy/.ssh
sudo touch /home/deploy/.ssh/authorized_keys
sudo chmod 600 /home/deploy/.ssh/authorized_keys
sudo chown -R deploy:deploy /home/deploy/.ssh
```

Добавить публичный ключ администратора:

```bash
echo "ssh-ed25519 PUBLIC_KEY_HERE operator@workstation" \
  | sudo tee -a /home/deploy/.ssh/authorized_keys
```

Проверить вход:

```bash
ssh deploy@SERVER_IP
whoami
hostname
```

### Hardening

Изменения в `sshd_config` выполняются только после подтверждения, что доступ
через `deploy` работает.

Минимальные целевые настройки:

```text
PermitRootLogin no
PasswordAuthentication no
```

После изменения конфигурации:

```bash
sudo systemctl reload ssh
```

### Риск

Некорректная SSH-настройка может заблокировать доступ к VM. До появления
стабильного Ansible-процесса hardening выполняется осторожно и только после
проверки альтернативного доступа к машине.

---

## Базовые пакеты

### Решение

На Linux-слое устанавливается только минимальный набор пакетов, нужный для
подготовки сервера и диагностики.

### Процедура

```bash
sudo apt update
sudo apt install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  git \
  unzip \
  htop \
  tree \
  jq \
  rsync \
  ufw
```

### Назначение пакетов

- `git` — получение кода проекта;
- `curl`, `gnupg`, `ca-certificates` — безопасная установка внешних репозиториев;
- `jq` — диагностика JSON;
- `rsync` — копирование данных и бэкапов;
- `ufw` — базовый firewall;
- `htop`, `tree` — эксплуатационная диагностика.

### Проверка

```bash
git --version
jq --version
rsync --version
ufw status
```

---

## Файловая структура

### Решение

Код, данные, логи и бэкапы должны храниться отдельно.

Контейнеры можно пересоздавать. Данные экспериментов, PostgreSQL data, результаты
обработки и бэкапы нельзя терять при пересборке контейнеров.

### Целевая структура

```text
/opt/complex_eeg/
  app/                  # код, compose-файлы, конфиги деплоя
  config/               # конфигурации сервисов
  scripts/              # эксплуатационные скрипты

/srv/complex_eeg/
  experiments/          # исходные пакеты экспериментов
  postgres/             # данные PostgreSQL volume/bind mount
  pipeline_results/     # результаты обработки
  upload_tmp/           # временная зона загрузок
  monitoring/           # данные/конфиги мониторинга, если нужно хранить на хосте

/backup/complex_eeg/
  files/                # бэкапы файлов экспериментов
  postgres/             # дампы PostgreSQL

/var/log/complex_eeg/
  app/                  # логи серверного приложения
  pipeline/             # логи обработки
  backup/               # логи бэкапов
```

### Процедура

```bash
sudo mkdir -p /opt/complex_eeg/app
sudo mkdir -p /opt/complex_eeg/config
sudo mkdir -p /opt/complex_eeg/scripts

sudo mkdir -p /srv/complex_eeg/experiments
sudo mkdir -p /srv/complex_eeg/postgres
sudo mkdir -p /srv/complex_eeg/pipeline_results
sudo mkdir -p /srv/complex_eeg/upload_tmp
sudo mkdir -p /srv/complex_eeg/monitoring

sudo mkdir -p /backup/complex_eeg/files
sudo mkdir -p /backup/complex_eeg/postgres

sudo mkdir -p /var/log/complex_eeg/app
sudo mkdir -p /var/log/complex_eeg/pipeline
sudo mkdir -p /var/log/complex_eeg/backup
```

### Права

```bash
sudo chown -R deploy:complex_eeg /opt/complex_eeg
sudo chown -R deploy:complex_eeg /srv/complex_eeg
sudo chown -R deploy:complex_eeg /backup/complex_eeg
sudo chown -R deploy:complex_eeg /var/log/complex_eeg

sudo chmod -R 750 /opt/complex_eeg
sudo chmod -R 2770 /srv/complex_eeg
sudo chmod -R 2770 /backup/complex_eeg
sudo chmod -R 2770 /var/log/complex_eeg
```

`/srv/complex_eeg`, `/backup/complex_eeg` и `/var/log/complex_eeg` получают
group-write и setgid bit, потому что в эти директории пишут контейнеры.
Прикладные контейнеры должны запускаться с UID/GID, совместимыми с
`deploy:complex_eeg`; это зафиксировано в `docker.md`.

### Проверка

```bash
tree -d -L 3 /opt/complex_eeg /srv/complex_eeg /backup/complex_eeg /var/log/complex_eeg
ls -ld /opt/complex_eeg /srv/complex_eeg /backup/complex_eeg /var/log/complex_eeg
```

Ожидаемый результат:

- директории существуют;
- владелец `deploy`;
- группа `complex_eeg`;
- доступ не открыт всем пользователям системы.

---

## Размещение кода

### Решение

Код проекта располагается в `/opt/complex_eeg/app`.

Данные экспериментов и бэкапы не должны попадать в Git checkout.

### Процедура

```bash
cd /opt/complex_eeg/app
git clone REPOSITORY_URL .
```

### Запрещено хранить в репозитории

- `.env` с секретами;
- пользовательские эксперименты;
- PostgreSQL data directory;
- бэкапы;
- временные файлы загрузки;
- production-секреты.

---

## Firewall

### Решение

Входящие соединения закрыты по умолчанию.

Разрешаются:

- SSH;
- HTTP/HTTPS после появления API/web.

Не разрешается:

- внешний доступ к PostgreSQL;
- внешний доступ к внутренним портам Docker-сервисов;
- внешний доступ к временным сервисам отладки.

### Процедура

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH
```

После появления API/web:

```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

Включение:

```bash
sudo ufw enable
sudo ufw status verbose
```

### Проверка

```bash
sudo ufw status numbered
```

Ожидаемый результат:

- SSH разрешён;
- HTTP/HTTPS разрешены только когда реально нужны;
- PostgreSQL-порт не открыт наружу.

---

## Время

### Решение

Системное время должно быть корректным. Логи, загрузки экспериментов, бэкапы,
алерты и статусы обработки зависят от timestamps.

### Проверка

```bash
timedatectl
```

Ожидаемый результат:

- time synchronization включена;
- timezone известен и зафиксирован;
- время VM не расходится с реальным временем.

### Настройка

Для первого стенда принимаем UTC:

```bash
sudo timedatectl set-timezone UTC
timedatectl
```

---

## Диск

### Решение

До развёртывания Docker и PostgreSQL нужно проверить, что VM имеет достаточно
места под данные.

Сервер должен хранить:

- исходные эксперименты;
- PostgreSQL data;
- результаты обработки;
- временные загрузки;
- бэкапы;
- Docker images;
- системные и прикладные логи.

### Проверка

```bash
df -h
lsblk
```

### Риск

Если диск недостаточен, нельзя компенсировать это отключением бэкапов. Нужно
увеличить диск, перенести файловое хранилище или согласовать другую стратегию
хранения.

---

## Linux-level логи

### Назначение

Системные логи нужны для диагностики проблем, которые находятся ниже уровня
приложения: SSH, Docker daemon, файловая система, нехватка ресурсов, ошибки
ядра.

### Базовые команды

```bash
journalctl -xe
journalctl -u ssh
dmesg -T
```

После установки Docker:

```bash
journalctl -u docker
```

Команды уровня Docker-сервисов будут описаны в `docker.md` и `runbook.md`.

---

## Валидация готовности

Linux-слой считается готовым, если выполнены проверки:

```bash
whoami
id deploy
getent group complex_eeg
git --version
jq --version
rsync --version
sudo ufw status verbose
timedatectl
df -h
tree -d -L 3 /opt/complex_eeg /srv/complex_eeg /backup/complex_eeg /var/log/complex_eeg
```

Критерии готовности:

- SSH-доступ работает;
- пользователь `deploy` создан;
- группа `complex_eeg` создана;
- директории существуют;
- права доступа настроены;
- firewall не блокирует SSH;
- PostgreSQL не открыт наружу;
- время синхронизировано;
- место на диске достаточно для первого стенда.

---

## Rollback / recovery

### Ошибка при создании пользователей

Безопасное действие:

- проверить `id deploy`;
- проверить `/etc/passwd`;
- при ошибке удалить только ошибочно созданного пользователя, если он ещё не
  владеет данными.

Нельзя:

- удалять пользователя `deploy`, если под ним уже созданы проектные данные, без
  предварительной проверки владельцев файлов.

### Ошибка прав на директории

Безопасное действие:

```bash
sudo chown -R deploy:complex_eeg /opt/complex_eeg /srv/complex_eeg /backup/complex_eeg /var/log/complex_eeg
sudo chmod -R 750 /opt/complex_eeg
sudo chmod -R 2770 /srv/complex_eeg /backup/complex_eeg /var/log/complex_eeg
```

Нельзя:

- применять `chmod -R 777`;
- удалять `/srv/complex_eeg` или `/backup/complex_eeg`.

### Ошибка firewall

Если есть риск потерять SSH-доступ:

- не включать `ufw`, пока не разрешён OpenSSH;
- проверять доступ через отдельную SSH-сессию;
- иметь доступ к консоли VM, если возможно.

---

## Передача в Ansible

В Ansible должны быть перенесены:

- установка базовых пакетов;
- создание группы `complex_eeg`;
- создание пользователя `deploy`;
- установка SSH-ключей для `deploy`;
- настройка SSH-политики;
- создание директорий;
- настройка владельцев и прав;
- базовые правила `ufw`;
- проверки готовности.

Целевое свойство Ansible-реализации: повторный запуск playbook не ломает
существующий сервер и не удаляет данные.

---

## Открытые вопросы

1. Финальный hostname VM.
2. Подтвердить UTC как финальный timezone/logging standard или заменить на
   лабораторный timezone.
3. Минимальный размер диска для первого стенда.
4. Будет ли `/backup/complex_eeg` находиться на отдельном диске.
5. Будет ли доступ к серверу только из локальной сети лаборатории или через VPN.
