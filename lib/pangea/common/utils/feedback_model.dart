import 'package:flutter/material.dart';

sealed class FeedbackState<T> {
  const FeedbackState();
}

class FeedbackIdle<T> extends FeedbackState<T> {}

class FeedbackLoading<T> extends FeedbackState<T> {}

class FeedbackLoaded<T> extends FeedbackState<T> {
  final T value;
  const FeedbackLoaded(this.value);
}

class FeedbackError<T> extends FeedbackState<T> {
  final Object error;
  const FeedbackError(this.error);
}

class FeedbackModel<T> extends ChangeNotifier {
  FeedbackState<T> _state = FeedbackIdle<T>();
  FeedbackState<T> get state => _state;

  void setState(FeedbackState<T> newState) {
    _state = newState;
    notifyListeners();
  }
}
