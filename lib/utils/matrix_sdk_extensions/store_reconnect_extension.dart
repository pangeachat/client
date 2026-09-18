import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';

extension StoreReconnectExtension on Client {
  /// Opens a fresh IndexedDB connection for a client with nothing in flight.
  ///
  /// iOS Safari drops a suspended tab's connection and the SDK keeps the dead
  /// handle, so the next store write throws and fails the login (#9163).
  Future<void> reconnectStore() async {
    if (!kIsWeb) return;
    final store = database;
    if (store is! MatrixSdkDatabase) return;
    await store.close();
    await store.open();
  }
}
