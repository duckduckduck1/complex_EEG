# Документация приложения оператора

Карта документации. Доки живут в репозитории и ревьюятся через PR (docs-as-code).

## Начать отсюда

- [Видение и цели](vision.md) — что строим, цели и не-цели MVP, глоссарий.
- [Архитектурные решения (ADR)](decisions/) — зафиксированные решения, по одному
  на файл.
- [Правила работы над проектом](../CONTRIBUTING.md) — ветки, документация,
  коммиты, PR, единый стиль.

## Как мы работаем (кратко)

- Каждое изменение — в **короткой ветке от `dev`** → PR в `dev` → ревью → merge →
  ветку удалить.
- PR держим **маленьким и сфокусированным**; перед merge тесты зелёные.
- **Документацию обновляем вместе с изменением** (docs-as-code); один факт — в
  одном месте.
- Коммиты на русском: краткий заголовок и буллеты «что и зачем».

Полные правила — в [CONTRIBUTING.md](../CONTRIBUTING.md).

## Контракты (`reference/`)

- [Формат пакета устройства](reference/device_packet.md) — контракт
  устройство ↔ приложение: BLE, декодирование сигнала, команда ФБМ.
- [Формат пакета эксперимента](reference/experiment_package.md) — что приложение
  пишет на диск и отдаёт наружу.

## Приложение (`flutter_app/`)

- [Обзор](flutter_app/README.md) ·
  [Архитектура](flutter_app/architecture.md) ·
  [Главный модуль](flutter_app/main_function.md) ·
  [Состояние (Bloc)](flutter_app/bloc.md) ·
  [BLE](flutter_app/ble.md) ·
  [Запись сигнала](flutter_app/recording.md) ·
  [Разметка](flutter_app/annotation.md) ·
  [Восстановление](flutter_app/recovery.md) ·
  [Визуализация](flutter_app/visualization.md) ·
  [Локальное хранение](flutter_app/storage.md) ·
  [Настройки](flutter_app/settings.md) ·
  [Эксперименты](flutter_app/experiments.md) ·
  [Тестирование](flutter_app/testing.md) ·
  [Утилиты](flutter_app/utils.md)

## Ресурсы

- `manuals/` — даташиты железа (АЦП `max30003.pdf`).
