import 'package:equatable/equatable.dart';

/// Базовая типизированная ошибка домена.
///
/// [code] — машиночитаемый код (стабильный, для логов и тестов).
/// [message] — безопасное для пользователя сообщение.
/// [cause] — техническая причина; пишется только в `app.log` и не показывается
/// пользователю (см. docs/flutter_app/architecture.md, «Обработка ошибок»).
sealed class Failure extends Equatable {
  const Failure({required this.code, required this.message, this.cause});

  final String code;
  final String message;
  final Object? cause;

  @override
  List<Object?> get props => [code, message];

  @override
  String toString() => 'Failure($code)';
}

/// Ошибки BLE-слоя (см. docs/flutter_app/ble.md).
final class BleFailure extends Failure {
  const BleFailure._({
    required super.code,
    required super.message,
    super.cause,
  });

  factory BleFailure.adapterUnavailable({Object? cause}) => BleFailure._(
    code: 'ble.adapter_unavailable',
    message: 'BLE-адаптер недоступен. Проверьте Bluetooth.',
    cause: cause,
  );

  factory BleFailure.permissionDenied({Object? cause}) => BleFailure._(
    code: 'ble.permission_denied',
    message: 'Нет разрешения на работу с Bluetooth.',
    cause: cause,
  );

  factory BleFailure.deviceNotFound({Object? cause}) => BleFailure._(
    code: 'ble.device_not_found',
    message: 'Устройство не найдено.',
    cause: cause,
  );

  factory BleFailure.connectionFailed({Object? cause}) => BleFailure._(
    code: 'ble.connection_failed',
    message: 'Не удалось подключиться к устройству.',
    cause: cause,
  );

  factory BleFailure.connectionLost({Object? cause}) => BleFailure._(
    code: 'ble.connection_lost',
    message: 'Связь с устройством потеряна.',
    cause: cause,
  );

  factory BleFailure.notificationSubscribeFailed({Object? cause}) =>
      BleFailure._(
        code: 'ble.notification_subscribe_failed',
        message: 'Не удалось подписаться на поток сигнала.',
        cause: cause,
      );

  factory BleFailure.packetDecodeFailed({Object? cause}) => BleFailure._(
    code: 'ble.packet_decode_failed',
    message: 'Ошибка декодирования пакета устройства.',
    cause: cause,
  );
}

/// Ошибки валидации входных данных и контрактов.
///
/// Коды совпадают с серверным валидатором, где это применимо
/// (см. docs/reference/experiment_package.md).
final class ValidationFailure extends Failure {
  const ValidationFailure._({required super.code, required super.message});

  factory ValidationFailure.experimentIdInvalid(String value) =>
      ValidationFailure._(
        code: 'validation.experiment_id_invalid',
        message:
            'Некорректный идентификатор эксперимента "$value": допустимы '
            'латиница, цифры, "_" и "-", длина 1–64 символа.',
      );
}
