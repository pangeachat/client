import 'dart:async';

class BaseController<T> {
  final StreamController<T> _stateListener = StreamController<T>();
  late Stream<T> stateStream;

  BaseController() {
    stateStream = _stateListener.stream.asBroadcastStream();
  }

  void dispose() {
    _stateListener.close();
  }

  void setState(T data) {
    _stateListener.add(data);
  }
}
