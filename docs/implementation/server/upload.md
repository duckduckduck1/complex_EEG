# upload.md

## Статус

Draft.

Документ описывает реализацию ручной выгрузки экспериментов из
Flutter-приложения на сервер.

---

## Назначение

Пользователь в приложении выбирает одну или несколько локальных папок
экспериментов. Приложение отправляет каждую папку как независимый upload flow.
Сервер принимает только завершённый пакет эксперимента.

Автоматическая выгрузка всех экспериментов на сервер не используется.

---

## Единица загрузки

Одна upload session соответствует одному `experiment_id`.

Допустимый формат `experiment_id`:

```text
^[a-zA-Z0-9_-]{1,64}$
```

Проверка выполняется при создании upload session. Любой `experiment_id`, который
может быть интерпретирован как путь (`../`, `/`, `\`, `.`, пробелы), отклоняется
до создания директорий.

Папка эксперимента на устройстве может называться пользовательским именем,
например:

```text
exp1/
  signal.bin
  experiment.json
  journal.ndjson
  app.log
```

Имя папки не является источником истины для `experiment_id`. Канонический
`experiment_id` берётся из `experiment.json` и запроса создания upload session.

---

## Временное хранилище

До успешной валидации файлы лежат во временной зоне:

```text
/srv/complex_eeg/upload_tmp/{upload_session_id}/
```

После успешной валидации исходный пакет переносится в постоянное хранилище:

```text
/srv/complex_eeg/experiments/{experiment_id}/source/
```

Если валидация не прошла, временный пакет сохраняется на ограниченное время для
диагностики или удаляется по cleanup policy. Решение фиксируется в настройке
retention для failed uploads.

---

## Состояния upload session

```text
created
uploading
completed
validating
accepted
failed
expired
cancelled
```

Связь с основным статусом эксперимента:

- `created/uploading` соответствует `uploading`;
- `completed` соответствует `uploaded`;
- `validating` соответствует `validating`;
- `accepted` соответствует `accepted`;
- `failed` соответствует `validation_failed` или upload error;
- `cancelled` соответствует `upload_cancelled`;
- `expired` соответствует `upload_expired`.

`upload_cancelled` и `upload_expired` не считаются принятыми сервером. Web UI
скрывает такие записи из основного списка по умолчанию, но Flutter-приложение
может увидеть их через status endpoints.

---

## TTL

Default TTL upload session:

```text
24h from created_at
```

Настройка:

```text
UPLOAD_SESSION_TTL_HOURS=24
```

После `expires_at` session переводится в `expired`, а связанный эксперимент в
`upload_expired`, если он ещё не был завершён. Cleanup удаляет временные файлы
после отдельного retention window, но не удаляет историю статуса.

---

## Создание session

При создании upload session сервер:

1. проверяет auth token;
2. проверяет payload;
3. проверяет `experiment_id` по regex `^[a-zA-Z0-9_-]{1,64}$`;
4. вычисляет `client_id` из bearer token;
5. проверяет, нет ли уже `accepted` эксперимента с таким `experiment_id`;
6. проверяет, нет ли активной session для того же `experiment_id`;
7. создаёт запись в PostgreSQL;
8. создаёт временную директорию;
9. возвращает `upload_session_id`.

Операция должна быть атомарной на уровне PostgreSQL. Уникальность активной
session защищается constraint или транзакционной блокировкой.

`upload_session_id` генерируется сервером в формате ULID.

`client_id` не приходит из payload. Его возвращает auth layer после проверки
bearer token. На первом стенде token валидируется через `AUTH_SECRET`, а в БД
сохраняется только логический `client_id`, не сам секрет.

Для первого стенда с одним shared `AUTH_SECRET` используется:

```text
client_id = flutter_app
```

При переходе на per-device tokens эта колонка станет идентификатором конкретного
устройства или установки приложения.

---

## Загрузка файлов

Файлы загружаются отдельно.

Правила:

- имя файла нормализуется и проверяется по allowlist;
- path traversal запрещён;
- размер файла проверяется до записи или во время streaming;
- файл пишется во временный путь с suffix `.part`;
- после успешной записи `.part` атомарно переименовывается в финальное имя;
- checksum можно добавить позже, если приложение начнёт его передавать.

Разрешённые файлы первого этапа:

```text
signal.bin
experiment.json
journal.ndjson
app.log
```

Обязательные:

```text
signal.bin
experiment.json
```

---

## Завершение upload

Endpoint `complete` переводит session в состояние `completed` только если:

- session существует;
- session принадлежит аутентифицированному клиенту;
- обязательные файлы загружены;
- файлы не находятся в состоянии `.part`;
- upload не expired.

После этого сервер запускает validation job.

Повторный `complete` идемпотентен:

- `completed` или `validating` возвращает `200` с текущим статусом;
- новый validation job не создаётся;
- `accepted` возвращает `200`;
- `cancelled`, `expired` или `failed` возвращает `409`.

Для первого стенда validation можно выполнить синхронно внутри API процесса, если
пакет небольшой. Целевое решение — вынести в service/worker, чтобы долгие
проверки не блокировали HTTP worker.

---

## Повторная загрузка

Если эксперимент уже `accepted`, сервер возвращает:

```text
409 experiment.already_accepted
```

Если предыдущая session была неполной или failed, приложение может создать новую
session для того же `experiment_id`, если серверная политика разрешает restart.

Правило первого стенда:

- `accepted` нельзя перезаписать через upload;
- `validation_failed` можно загрузить заново только новой session;
- старая failed session остаётся в истории.

---

## Status check и cancel

Flutter-приложение может проверить session после рестарта:

```http
GET /api/v1/uploads/{upload_session_id}
```

Если приложение не сохранило `upload_session_id`, оно создаёт новую session.
Сервер либо создаёт её, либо возвращает конфликт с информацией об активной
session для того же `experiment_id`.

Пользовательская отмена:

```http
DELETE /api/v1/uploads/{upload_session_id}
```

Cancel переводит session в `cancelled`, эксперимент в `upload_cancelled` и
оставляет временные файлы до cleanup.

---

## Cleanup

Периодический cleanup удаляет:

- expired sessions;
- `.part` файлы старше configured TTL;
- временные директории failed sessions после retention window.

Cleanup не удаляет:

- permanent source files;
- accepted experiments;
- pipeline results;
- записи истории в PostgreSQL.

---

## Проверки реализации

Минимальные тесты:

- нельзя создать session без auth;
- нельзя создать session для уже accepted `experiment_id`;
- можно загрузить обязательные файлы;
- `complete` без `signal.bin` возвращает ошибку;
- path traversal в имени файла отклоняется;
- повторный `complete` идемпотентен;
- `GET /uploads/{upload_session_id}` возвращает состояние после рестарта app;
- `DELETE /uploads/{upload_session_id}` переводит session в `cancelled`;
- expired session переводит experiment в `upload_expired`;
- failed upload не создаёт `accepted`;
- успешный upload запускает validation.
