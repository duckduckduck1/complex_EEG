import 'package:equatable/equatable.dart';

import '../errors/failures.dart';
import '../result/result.dart';
import 'ulid.dart';

/// Идентификатор эксперимента, совместимый с сервером.
///
/// Значение соответствует серверному regex `^[a-zA-Z0-9_-]{1,64}$`
/// (см. docs/reference/experiment_package.md). Новые ID генерируются как
/// `exp_<ULID>` и не зависят от пользовательского имени папки.
class ExperimentId extends Equatable {
  const ExperimentId._(this.value);

  /// Сгенерировать новый идентификатор вида `exp_<ULID>`.
  factory ExperimentId.generate({UlidGenerator? generator}) {
    final ulid = (generator ?? UlidGenerator()).generate();
    return ExperimentId._('exp_$ulid');
  }

  /// Каноническое строковое значение идентификатора.
  final String value;

  static final RegExp _pattern = RegExp(r'^[a-zA-Z0-9_-]{1,64}$');

  /// Проверить строку на соответствие контракту сервера.
  static bool isValid(String value) => _pattern.hasMatch(value);

  /// Разобрать существующее значение, вернув типизированную ошибку при сбое.
  static Result<ExperimentId, ValidationFailure> parse(String value) {
    if (!isValid(value)) {
      return Err(ValidationFailure.experimentIdInvalid(value));
    }
    return Ok(ExperimentId._(value));
  }

  @override
  List<Object?> get props => [value];

  @override
  String toString() => value;
}
