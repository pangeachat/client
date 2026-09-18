import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';

extension StoreReconnectExtension on Client {
  static const Duration _reconnectTimeout = Duration(seconds: 5);

  /// Reopens an IndexedDB connection the browser has closed (iOS Safari does,
  /// on a suspended tab) and says whether it had to. Nothing may be in flight.
  Future<bool> reconnectStoreIfClosed() async {
    if (!kIsWeb) return false;
    final store = database;
    if (store is! MatrixSdkDatabase) return false;
    return _reconnectIfClosed(store).timeout(_reconnectTimeout);
  }

  Future<bool> _reconnectIfClosed(MatrixSdkDatabase store) async {
    try {
      // The SDK answers most reads from memory; this one always asks the
      // browser, so it is what a closed connection fails.
      await store.getAccountData();
      return false;
    } catch (e, s) {
      ErrorHandler.logErrorOnce(
        key: 'store_reconnect',
        e: e,
        s: s,
        level: SentryLevel.warning,
        data: {'recovery': 'reopened the store connection'},
      );
    }
    await store.close();
    await store.open();
    return true;
  }
}
