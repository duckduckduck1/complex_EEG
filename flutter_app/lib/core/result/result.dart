import 'package:equatable/equatable.dart';

/// Результат операции: успешное значение [Ok] или типизированная ошибка [Err].
///
/// Репозитории и use case возвращают `Result`, а не пробрасывают сырые
/// исключения наружу (см. docs/flutter_app/storage.md и architecture.md).
sealed class Result<T, F> extends Equatable {
  const Result();

  /// `true`, если это [Ok].
  bool get isOk => this is Ok<T, F>;

  /// `true`, если это [Err].
  bool get isErr => this is Err<T, F>;

  /// Значение при успехе или `null`.
  T? get valueOrNull => switch (this) {
    Ok<T, F>(:final value) => value,
    Err<T, F>() => null,
  };

  /// Ошибка при сбое или `null`.
  F? get failureOrNull => switch (this) {
    Ok<T, F>() => null,
    Err<T, F>(:final failure) => failure,
  };

  /// Свернуть оба варианта в одно значение.
  R fold<R>(R Function(T value) onOk, R Function(F failure) onErr) =>
      switch (this) {
        Ok<T, F>(:final value) => onOk(value),
        Err<T, F>(:final failure) => onErr(failure),
      };

  /// Преобразовать успешное значение, сохранив ошибку без изменений.
  Result<R, F> map<R>(R Function(T value) transform) => switch (this) {
    Ok<T, F>(:final value) => Ok<R, F>(transform(value)),
    Err<T, F>(:final failure) => Err<R, F>(failure),
  };

  /// Вернуть значение или результат [fallback] при ошибке.
  T getOrElse(T Function(F failure) fallback) => switch (this) {
    Ok<T, F>(:final value) => value,
    Err<T, F>(:final failure) => fallback(failure),
  };
}

/// Успешный результат со значением [value].
final class Ok<T, F> extends Result<T, F> {
  const Ok(this.value);

  final T value;

  @override
  List<Object?> get props => [value];
}

/// Неуспешный результат с типизированной ошибкой [failure].
final class Err<T, F> extends Result<T, F> {
  const Err(this.failure);

  final F failure;

  @override
  List<Object?> get props => [failure];
}
