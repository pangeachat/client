/// A generic sealed class that represents the state of an asynchronous operation.
sealed class AsyncState<T> {
  /// Base constructor for all asynchronous state variants.
  const AsyncState();

  /// Represents an idle state before any asynchronous work has begun.
  const factory AsyncState.idle() = AsyncIdle<T>;

  /// Represents an in-progress loading state.
  const factory AsyncState.loading() = AsyncLoading<T>;

  /// Represents a completed asynchronous operation with a successful [value].
  const factory AsyncState.loaded(T value) = AsyncLoaded<T>;

  /// Represents a failed asynchronous operation with an [error].
  const factory AsyncState.error(Object error) = AsyncError<T>;
}

/// The idle state of an [AsyncState], indicating no active or completed work.
///
/// Use this as the initial state before triggering an async operation.
class AsyncIdle<T> extends AsyncState<T> {
  /// Creates an idle [AsyncState].
  const AsyncIdle();
}

/// The loading state of an [AsyncState], indicating that work is in progress.
///
/// This state is typically used to show a loading spinner or progress indicator.
class AsyncLoading<T> extends AsyncState<T> {
  /// Creates a loading [AsyncState].
  const AsyncLoading();
}

/// The success state of an [AsyncState], containing a completed [value].
///
/// This state indicates that the asynchronous work finished successfully.
class AsyncLoaded<T> extends AsyncState<T> {
  /// The result of the successful asynchronous operation.
  final T value;

  /// Creates a loaded [AsyncState] with a [value].
  const AsyncLoaded(this.value);
}

/// The error state of an [AsyncState], containing an [error].
///
/// This state indicates that the asynchronous work failed.
class AsyncError<T> extends AsyncState<T> {
  /// The error produced during the asynchronous operation.
  final Object error;

  /// Creates an error [AsyncState] with an [error].
  const AsyncError(this.error);
}
