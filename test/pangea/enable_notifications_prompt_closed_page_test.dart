import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart' show Client;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/notifications/enable_notifications_dialog.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/local_notifications_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../utils/test_client.dart';

/// Skips `initState` (and so `initMatrix()`), which wires push, notification
/// listeners and the Pangea controller; the prompt reads only `client`.
/// Mirrors `matrix_state_login_race_test.dart`.
class _TestMatrixState extends MatrixState {
  @override
  // ignore: must_call_super
  void initState() {}
}

class _TestMatrix extends Matrix {
  const _TestMatrix({
    required super.clients,
    required super.store,
    required super.child,
  });

  @override
  MatrixState createState() => _TestMatrixState();
}

/// #9528 (CLIENT-F0K) — the "turn on notifications" prompt awaits the
/// permission check before it opens its dialog. When the page that asked
/// closed during that wait, `showDialog` ran on an unmounted context and threw
/// a null check in `Navigator.of`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;
  late SharedPreferences store;
  late Completer<int> permissionStatus;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUpAll(() async {
    dotenv.testLoad(
      mergeWith: {'SYNAPSE_URL': 'https://fakeserver.notexisting'},
    );
    final tempDir = await Directory.systemTemp.createTemp('notif_prompt');
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (m) async => tempDir.path,
    );
    await GetStorage.init('env_override');
    await GetStorage.init('notifications_request_storage');
    SharedPreferences.setMockInitialValues({});
    store = await SharedPreferences.getInstance();
    client = await prepareTestClient(loggedIn: true);
    // Held open by each test, so the page can close mid-check.
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/permissions/methods'),
      (call) async => call.method == 'checkPermissionStatus'
          ? permissionStatus.future
          : null,
    );
  });

  tearDownAll(() async {
    await client.dispose();
  });

  const denied = 0; // PermissionStatus.denied

  final navigator = GlobalKey<NavigatorState>();

  Future<MatrixState> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: _TestMatrix(
          clients: [client],
          store: store,
          child: const SizedBox(),
        ),
      ),
    );
    await tester.pumpAndSettle(); // the navigator builds once L10n has loaded
    final matrix = tester.state<_TestMatrixState>(find.byType(_TestMatrix));
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Text('course page')),
    );
    await tester.pumpAndSettle();
    return matrix;
  }

  testWidgets(
    'a page that closed during the check gets no dialog',
    timeout: const Timeout(Duration(seconds: 30)),
    (tester) async {
      permissionStatus = Completer<int>();
      final matrix = await pumpPage(tester);

      final prompt = matrix.showEnableNotificationsDialog(
        tester.element(find.text('course page')),
      );
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      permissionStatus.complete(denied);

      // The storage read is real I/O, which fake time never runs.
      // Before the fix this threw: a null check in release builds (CLIENT-F0K),
      // "This BuildContext is no longer valid" in debug.
      await tester.runAsync(() => prompt);
      await tester.pump();
      expect(find.byType(EnableNotificationsDialog), findsNothing);
    },
  );

  testWidgets(
    'a page that stays open still gets the dialog',
    timeout: const Timeout(Duration(seconds: 30)),
    (tester) async {
      permissionStatus = Completer<int>();
      final matrix = await pumpPage(tester);

      unawaited(
        matrix.showEnableNotificationsDialog(
          tester.element(find.text('course page')),
        ),
      );
      permissionStatus.complete(denied);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();

      expect(find.byType(EnableNotificationsDialog), findsOneWidget);
    },
  );
}
