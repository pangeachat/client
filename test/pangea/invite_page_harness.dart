import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/chat_details/invite/pangea_invitation_selection.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_pangea_controller.dart';

/// Pumps the real invite page ([PangeaInvitationSelection]) under a [Matrix]
/// that skips `initMatrix()`. Create it once, in `setUpAll`.
class InvitePageHarness {
  final SharedPreferences _store;

  InvitePageHarness._(this._store);

  /// Avatars read BotName.byEnvironment → Environment.botName, which needs
  /// GetStorage (path_provider-backed) and dotenv to be readable.
  static Future<InvitePageHarness> create() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final tempDir = await Directory.systemTemp.createTemp('invite_page');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(
      mergeWith: {
        'BOT_NAME': 'pangeabot',
        'SYNAPSE_URL': 'https://fakeServer.notExisting',
      },
    );
    SharedPreferences.setMockInitialValues({});
    MatrixState.pangeaController = FakePangeaController();
    return InvitePageHarness._(await SharedPreferences.getInstance());
  }

  /// English throughout — one locale per isolate, or a second set of delegates
  /// loads asynchronously and leaves the subtree empty for the pumped frames.
  ///
  /// Bounded pumps, not pumpAndSettle: the refer-a-friend image at the list's
  /// tail shows a progress placeholder that never resolves under test.
  ///
  /// Give the room a join code: without one, a privileged viewer makes the
  /// page request one, and that request's timeout outlives the pumped tree.
  Future<void> pump(
    WidgetTester tester, {
    required Client client,
    required String roomId,
  }) async {
    await tester.pumpWidget(
      _TestMatrix(
        clients: [client],
        store: _store,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: PangeaInvitationSelection(
            roomId: roomId,
            embeddedCloseButton: const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }
}

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
