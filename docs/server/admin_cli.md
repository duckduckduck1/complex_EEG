# Admin CLI

## Статус

Implemented.

Документ описывает служебный CLI серверного приложения. CLI нужен для действий,
которые выполняет оператор стенда или администратор, но которые не должны быть
публичными HTTP endpoints.

---

## Назначение

Первый обязательный сценарий CLI — создание пользователя Web UI после применения
миграций PostgreSQL.

Публичной регистрации в MVP нет. Пользователей создаёт администратор проекта.

---

## Команды

### Создать пользователя Web UI

После `pip install -e ".[dev]"` доступна console command:

```bash
complex-eeg users create --username admin --role admin
```

Также команда может запускаться без console script:

```bash
python -m app.cli users create --username admin --role admin
```

По умолчанию пароль вводится интерактивно через скрытый prompt:

```text
Password:
Repeat password:
```

Для VM, CI или bootstrap-скрипта используется stdin:

```bash
printf '%s\n' 'change-this-password' \
  | complex-eeg users create --username admin --role admin --password-stdin
```

В PowerShell:

```powershell
"change-this-password" | complex-eeg users create --username admin --role admin --password-stdin
```

---

## Правила

Username:

```text
^[a-zA-Z0-9_.@-]{1,128}$
```

Разрешённые роли:

```text
viewer
operator
admin
```

Минимальная длина пароля:

```text
12 characters
```

Пароль не хранится в plain text. CLI передаёт пароль в service layer, где
создаётся hash формата:

```text
pbkdf2_sha256$iterations$salt$hash
```

---

## Exit Codes

```text
0 - пользователь создан
1 - ошибка PostgreSQL/SQLAlchemy
2 - ожидаемая ошибка ввода или бизнес-правила
```

Примеры ожидаемых ошибок:

- username уже существует;
- username не соответствует regex;
- role не входит в список разрешённых;
- пароль короче минимальной длины;
- интерактивно введённые пароли не совпадают.

---

## Ограничения

CLI предполагает, что:

- миграции PostgreSQL уже применены;
- таблица `users` существует;
- переменные подключения к БД доступны через environment или `.env`;
- команда запускается из server environment, где установлен пакет
  `complex-eeg-server`.

CLI не создаёт таблицы и не заменяет Alembic migrations.

