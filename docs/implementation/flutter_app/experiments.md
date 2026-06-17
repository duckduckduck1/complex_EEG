# experiments.md

## Статус

Draft.

Документ описывает работу со списком сохранённых экспериментов, открытие
эксперимента, локальные действия и связь со статусами сервера.

---

## BLoC

```text
ExperimentIndexBloc
ExperimentListFilterCubit
ExperimentViewerBloc
ExperimentActionsBloc
ExperimentServerStatusBloc
```

Список, фильтры, выбранный эксперимент и действия с локальными файлами
управляются через BLoC/Cubit.

---

## Experiment list

Экран сохранённых экспериментов показывает:

```text
display_name
experiment_id
created_at
duration
sample_count
recording_status
server_status
last_error
folder_path user-visible optional
```

`folder_path` можно показывать пользователю как справочную информацию, но
внутренние операции не должны строиться на произвольном вводе пути.

---

## Filters and search

Фильтры:

```text
recording_status
server_status
date_from
date_to
text search over display_name and experiment_id
```

Sort:

```text
created_at_desc
created_at_asc
display_name_asc
server_status_asc
```

---

## Open experiment

При открытии сохранённого эксперимента:

1. app читает local index;
2. проверяет наличие папки;
3. проверяет `signal.bin`;
4. читает `experiment.json`;
5. создаёт `ExperimentViewerBloc`;
6. создаёт scoped `AnnotationBloc` и `VisualizationBloc`.

BLE connection не нужен для просмотра сохранённого эксперимента.

---

## Export package

Экспорт в серверный пакет означает, что папка содержит:

```text
signal.bin
experiment.json
journal.ndjson optional
app.log optional
```

Перед ручной отправкой `ServerUploadBloc` запускает preflight validation из
`server_sync.md`.

---

## Local delete/archive

Удаление локальной папки:

- только вручную;
- только после подтверждения пользователя;
- не выполняется автоматически после server accepted;
- не удаляет данные на сервере.

Archive action может переместить папку в выбранное пользователем место, но
должна обновить local index.

---

## Rebuild index

Если local index повреждён, app может пересканировать `experiments_root`.

Rebuild uses:

- `experiment.json`;
- `signal.bin` size;
- `journal.ndjson`, если final JSON missing;
- folder metadata.

---

## Проверки реализации

- список строится из BLoC state;
- удаление требует подтверждения;
- accepted experiment не удаляется автоматически;
- open saved experiment works offline;
- index rebuild восстанавливает experiment records;
- server status refresh не блокирует локальный просмотр.
