# Dev-утилиты

Скрипты для локальной отладки. В production не используются.

## generate_test_experiment.py

Создаёт валидный пакет эксперимента (`signal.bin` + `experiment.json`) по
контракту [docs/reference/experiment_package.md](../../docs/reference/experiment_package.md),
чтобы прогонять серверный upload flow без устройства и Flutter-приложения.

```bash
python scripts/dev/generate_test_experiment.py --out ./tmp_exp
```

Опции: `--experiment-id`, `--samples` (по умолчанию 2500 = 10 с при 250 Гц),
`--segments`, `--animal-id`, `--with-optional` (добавить `journal.ndjson` и
`app.log`). Корректность пакета покрыта тестом
`server/tests/test_generate_test_experiment.py`.
