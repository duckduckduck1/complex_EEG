# Синхронизация с сервером

## Статус

Draft.

Документ описывает MVP-взаимодействие Flutter-приложения с серверным контуром.
В первом стенде Flutter-приложение не выполняет HTTP upload на сервер. Его задача
— создать корректный experiment package, который пользователь затем загружает
через Web UI.

Название файла сохранено для связности документации; фактически документ
описывает package handoff, а не сетевую синхронизацию.

---

## BLoC

```text
ExperimentPackageValidationCubit
PackageExportBloc
```

Эти BLoC/Cubit живут на экране сохранённых экспериментов или в export dialog.
Они не хранят server auth token и не вызывают upload API.

---

## MVP handoff flow

1. User finishes recording.
2. App finalizes `experiment.json`.
3. App keeps experiment as a local folder.
4. User opens saved experiments list.
5. User selects experiment package export/check action.
6. App validates that the package is ready for server upload.
7. App shows folder location or creates an optional `.zip` export.
8. User opens server Web UI in browser.
9. User uploads the folder/archive through Web UI.

The app never starts upload automatically after recording stop.

---

## Package preflight

Before handoff, Flutter checks:

- `experiment.json` exists;
- `signal.bin` exists;
- `experiment_id` matches `^[a-zA-Z0-9_-]{1,64}$`;
- `signal.bin` size is divisible by 4;
- required server compatibility fields exist;
- segments fit inside sample count;
- required files are readable.

Server repeats validation after upload. Flutter preflight is a user convenience,
not a security boundary.

---

## Export formats

MVP supports:

```text
experiment folder
optional .zip archive
```

The canonical package content is:

```text
signal.bin
experiment.json
journal.ndjson optional
app.log optional
```

If `.zip` export is implemented, archive entries must be relative paths. Absolute
Windows paths must not be embedded into the archive.

---

## Server API usage

No server API is required by the Flutter app in MVP.

The following may be added later as a separate feature:

```text
POST /api/v1/uploads
PUT /api/v1/uploads/{upload_session_id}/files/{file_name}
POST /api/v1/uploads/{upload_session_id}/complete
POST /api/v1/experiments/status-batch
```

Future direct upload must reuse the same package contract and must not change
recording behavior.

---

## Local status

Flutter stores local package readiness, not authoritative server status.

Canonical local package statuses:

```text
not_ready
ready
exported
export_error
```

Server status is authoritative only in Web UI for the MVP. If status sync is
added later, it must be optional and must not block local viewing or recording.

---

## Error handling

Package validation errors map to user messages:

```text
package.missing_experiment_json
package.missing_signal_bin
package.invalid_experiment_id
package.signal_size_invalid
package.segment_out_of_bounds
package.unreadable_file
package.export_failed
```

The app writes technical details to `app.log`, but must not rewrite source files
silently.

---

## Local folder policy

After server acceptance through Web UI:

- local folder is not deleted automatically;
- app may not know server status in MVP;
- user may delete/archive local copy manually;
- app must ask confirmation before deletion.

---

## Проверки реализации

- package validation works offline;
- missing `signal.bin` blocks export;
- missing `experiment.json` blocks export;
- invalid `experiment_id` blocks export;
- `.zip` export never contains absolute paths;
- export does not modify `signal.bin`;
- local folder remains after export.
