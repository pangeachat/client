import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';

extension StoreReconnectExtension on Client {
  /// Reopens this client's IndexedDB connection if the browser has closed it,
  /// and says whether it had to. For a client with nothing in flight.
  ///
  /// iOS Safari drops a suspended tab's connection and the SDK keeps the dead
  /// handle, so the next store write throws and fails the login (#9163).
  Future<bool> reconnectStoreIfClosed() async {
    if (!kIsWeb) return false;
    final store = database;
    if (store is! MatrixSdkDatabase) return false;
    try {
      // The SDK answers most reads from memory; this one always asks the
      // browser, so it is what a closed connection fails.
      await store.getAccountData();
      return false;
    } catch (e, s) {
      Logs().w('Store connection is closed; reopening it', e, s);
    }
    await store.close();
    await store.open();
    return true;
  }
}
