import 'package:equatable/equatable.dart';

/// Один декодированный отсчёт ЭЭГ в микровольтах.
///
/// Всё приложение работает только с уже декодированным значением; сырые байты
/// устройства живут лишь в BLE-слое (см. docs/flutter_app/ble.md). В `signal.bin`
/// значение пишется как `int32` little-endian
/// (см. docs/reference/experiment_package.md).
class EegSample extends Equatable {
  const EegSample({required this.valueMicrovolts});

  /// Амплитуда в микровольтах.
  final int valueMicrovolts;

  @override
  List<Object?> get props => [valueMicrovolts];
}
