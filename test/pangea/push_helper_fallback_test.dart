import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/push_helper.dart';
import 'get_test_client.dart';

/// Sentry CLIENT-EPC / EPB (#9053): one failed notification, reported twice.
///
/// `pushHelper`'s catch shows a fallback notification and rethrows. That
/// fallback was unawaited, and it fails for exactly the reasons the original
/// did — so its rejection surfaced as a SECOND, caller-less unhandled async
/// error stacked on the one being rethrown. The fallback is best-effort: its
/// failure must stay inside `pushHelper`.
class _FailingPlugin implements FlutterLocalNotificationsPlugin {
  int showCalls = 0;

  /// The exact iOS failure from the report.
  static PlatformException get _notAuthorized => PlatformException(
    code: 'Error 2003',
    message:
        'Repository could not save notification. Source is not authorized.',
    details: 'UNErrorDomain',
  );

  @override
  Future<void> show(
    int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails, {
    String? payload,
  }) async {
    showCalls++;
    throw _notAuthorized;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late L10n l10n;

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('push_helper');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => tempDir.path,
        );
    // Preloaded: one locale per test file, and the catch path needs a real
    // L10n rather than looking one up mid-test.
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  test(
    'a failing fallback notification does not orphan a second error',
    () async {
      final client = await getTestClient();
      addTearDown(client.dispose);
      final plugin = _FailingPlugin();

      // No such event on the fake homeserver, so _tryPushHelper's own event
      // lookup throws and lands in the catch that shows the fallback.
      final notification = PushNotification(
        counts: PushNotificationCounts(unread: 0),
        devices: const [],
        roomId: '!nope:fakeServer.notExisting',
        eventId: '\$nope',
      );

      await expectLater(
        pushHelper(
          notification,
          client: client,
          l10n: l10n,
          flutterLocalNotificationsPlugin: plugin,
        ),
        throwsA(allOf(isA<MatrixException>(), isNot(isA<PlatformException>()))),
        reason:
            'the ORIGINAL lookup failure reaches the caller — the fallback '
            "notification's own failure neither replaces it nor escapes beside it",
      );

      expect(
        plugin.showCalls,
        1,
        reason:
            'the fallback ran once and its failure stayed inside pushHelper',
      );
    },
  );
}
