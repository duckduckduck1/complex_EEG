# server_sync.md

## Статус

Draft.

Документ описывает реализацию ручной отправки локальных экспериментов на сервер.

---

## BLoC

```text
ServerAuthCubit
ServerUploadBloc
UploadQueueBloc
ExperimentServerStatusBloc
```

Загрузка нескольких экспериментов управляется queue BLoC. Каждый элемент очереди
имеет независимый state.

---

## Auth

Flutter app uses server bearer token:

```http
Authorization: Bearer <token>
```

Token хранится в settings secure storage или в защищённой конфигурации стенда.
Token не пишется в `app.log`.

На первом стенде серверный `client_id` будет `flutter_app`.

---

## Manual upload flow

1. User opens saved experiments list.
2. User selects one or more experiment folders.
3. App validates local package.
4. App creates upload session.
5. App uploads files.
6. App completes upload.
7. App polls upload/experiment status.
8. Local index updates server status.

Upload is never automatic after recording stop.

---

## Client-side preflight

Before upload:

- `experiment.json` exists;
- `signal.bin` exists;
- `experiment_id` matches `^[a-zA-Z0-9_-]{1,64}$`;
- `signal.bin` size divisible by 4;
- segments fit inside sample count;
- required files readable.

Server repeats validation.

---

## Upload session API

Used endpoints:

```text
POST /api/v1/uploads
GET /api/v1/uploads/{upload_session_id}
PUT /api/v1/uploads/{upload_session_id}/files/{file_name}
POST /api/v1/uploads/{upload_session_id}/complete
DELETE /api/v1/uploads/{upload_session_id}
GET /api/v1/experiments/{experiment_id}/status
POST /api/v1/experiments/status-batch
```

`status-batch` sends max 100 IDs per request.

---

## Upload statuses

Canonical local statuses are defined in `storage.md`. `ServerUploadBloc` uses the
same enum and does not introduce additional string values.

---

## Resume after app restart

If app has saved `active_upload_session_id` in the local experiment index, it
calls:

```http
GET /api/v1/uploads/{upload_session_id}
```

If session is still active, upload can continue or be cancelled.

If session is absent/expired and experiment is not accepted, app creates a new
session.

---

## Cancellation

If user cancels upload:

1. `ServerUploadBloc` sends `DELETE /uploads/{id}`;
2. local status becomes `cancelled`;
3. local experiment folder remains unchanged.

If network is unavailable during cancel, app marks local upload as
`cancel_pending` and retries or lets server TTL expire.

---

## Retry policy

`upload_retry_count` from settings controls retry attempts.

Retryable:

```text
network.unavailable
request.timeout
server.temporary_unavailable
```

Not retryable:

```text
auth.invalid_token
experiment.already_accepted
validation.*
upload.session_expired
request.invalid_payload
```

Backoff:

```text
retry up to upload_retry_count times
delay after attempt 1: 1s
delay after attempt 2: 2s
delay after attempt 3 and later: 5s
```

Retries never create a second upload session while `active_upload_session_id`
exists.

---

## Error handling

Server errors map to user messages:

```text
experiment.already_accepted
upload.session_expired
upload.session_not_found
validation.missing_file
validation.segment_out_of_bounds
network.unavailable
auth.invalid_token
```

The app stores last server error in local index.

---

## Local folder policy

After successful server acceptance:

- local folder is not deleted;
- user may delete/archive manually;
- app must ask confirmation before deletion;
- deletion is allowed only for local copy, not server data.

---

## Проверки реализации

- upload cannot start without auth token;
- selecting 3 folders creates 3 independent queue items;
- failure of one upload does not stop others;
- cancelled upload calls server cancel endpoint;
- after app restart active upload status can be restored;
- local folder remains after accepted.
