# Приложение оператора (Flutter)

Windows-приложение оператора «Лаборатории Умного сна»: приём сигнала ЭЭГ с
устройства по BLE, запись, разметка, фотобиомодуляция и подготовка пакета
эксперимента для ручной загрузки через Web UI сервера.

Дизайн и контракты — в [docs/flutter_app/](../docs/flutter_app/) и
[docs/reference/](../docs/reference/). Архитектура и правила слоёв —
[docs/flutter_app/architecture.md](../docs/flutter_app/architecture.md).

## Требования

- Flutter (stable) с включённой поддержкой Windows desktop (`flutter config
  --enable-windows-desktop`).
- Зависимости: `flutter pub get`.

## Запуск и проверки

```bash
flutter pub get        # зависимости
flutter analyze        # статический анализ
flutter test           # юнит- и виджет-тесты
dart format .          # форматирование
flutter run -d windows # запуск приложения
```

## Что уже реализовано

Каркас приложения и доменное ядро сигнала под зафиксированные контракты:

- `lib/core/` — общие примитивы: `Result`, типизированные `Failure`,
  генерация ID (`ULID`, `ExperimentId` под серверный regex), отсчёт `EegSample`.
- `lib/features/devices/` — конфигурация тракта (`DeviceSignalConfig`), декодер
  потока устройства в мкВ (`BleSampleDecoder`) и команда ФБМ (`FbmCommand`)
  по [контракту устройства](../docs/reference/device_packet.md).

Слои фич (`presentation/application/domain/data`), BLE-транспорт, запись на диск
и экраны добавляются следующими слайсами.
