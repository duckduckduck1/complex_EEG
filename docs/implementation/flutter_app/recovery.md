# recovery.md

## Статус

Draft.

Документ описывает восстановление после краша приложения или системы.

---

## BLoC

```text
RecoveryBloc
ExperimentIndexBloc
RecordingBloc
```

Recovery is explicit. User sees recovered sessions and chooses action.

---

## Startup scan

At app startup:

1. scan experiments root;
2. find folders with `journal.ndjson` and missing/incomplete final JSON;
3. compute `signal.bin` saved sample count;
4. replay journal up to valid sample count;
5. build recovery candidate;
6. show recovery UI.

---

## Signal size truth

Actual saved samples:

```text
saved_sample_count = floor(file_size_bytes / 4)
```

If file size is not divisible by 4:

- truncate only after explicit recovery decision;
- log recovery action;
- preserve original copy if possible.

---

## Journal replay

Journal events that reference samples beyond `saved_sample_count` are not applied
silently.

Rules:

- completed segment beyond saved size is clipped or rejected with explicit note;
- open segment closes at last saved sample;
- labels beyond saved data are marked invalid and excluded from final JSON until
  user reviews;
- recovery action writes `recovery_performed` event.

---

## User choices

Recovery UI offers:

```text
continue_recording
finalize_experiment
open_readonly
discard_recovery_candidate
```

Discard never deletes files immediately. It hides candidate from startup list or
moves it to ignored state after confirmation.

---

## Continue recording

If user continues:

1. app computes `valid_byte_length = floor(file_size_bytes / 4) * 4`;
2. if `signal.bin` has a partial int32 tail, writer truncates file to
   `valid_byte_length`;
3. app writes `recovery_performed` event to `journal.ndjson`;
4. app reopens writer in append mode;
5. starts a new segment;
6. waits for device connection;
7. resumes only after explicit user action.

The gap between crash and resume is not signal.

---

## Finalize

If user finalizes:

1. app creates final `experiment.json` from recovered state;
2. invalid future annotations are omitted with warning;
3. local index updates experiment as stopped/finalized.

---

## Проверки реализации

- app can detect unfinished journal;
- saved sample count comes from file size;
- journal events beyond saved samples are not blindly accepted;
- recovery does not auto-delete files;
- continue recording appends to same signal file and starts new segment.
