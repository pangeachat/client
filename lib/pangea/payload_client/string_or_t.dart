final class _StringCase<T> extends StringOr<T> {
  final String value;
  const _StringCase(this.value);
}

final class _ValueCase<T> extends StringOr<T> {
  final T value;
  const _ValueCase(this.value);
}

sealed class StringOr<T> {
  const StringOr();

  // Convenience factory constructors
  const factory StringOr.string(String value) = _StringCase<T>;
  const factory StringOr.value(T value) = _ValueCase<T>;

  // Decode one element that is either a String or a T
  factory StringOr.fromJson(
    Object? json,
    T Function(Object? json) decodeT,
  ) {
    if (json is String) return StringOr.string(json);
    return StringOr.value(decodeT(json));
  }

  // Encode one element back to JSON
  Object? toJson(Object? Function(T v) encodeT) => switch (this) {
        _StringCase(value: final s) => s,
        _ValueCase(value: final v) => encodeT(v),
      };
}
