import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/user_profile_builder.dart';

/// Covers #8192: participants of a session the learner has not joined rendered
/// as their localpart, because the name was resolved upstream from room state
/// that doesn't exist for such a session. Cards now name a bare user id from
/// their fetched global profile — this is the resolution order that produces.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bot = '@bot:test.pangea.chat';
  late L10n l10n;

  setUpAll(() async {
    // localizedPangeaUserName → BotName.byEnvironment → Environment.botName
    // touches the GetStorage('env_override') box, which needs path_provider.
    // Stub the channel to a temp dir so the box initializes silently (its read
    // returns null and botName falls back to dotenv) — same pattern as
    // activity_session_join_gate_test.dart.
    final tempDir = await Directory.systemTemp.createTemp('display_name_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  setUp(() => dotenv.testLoad(mergeWith: {'BOT_NAME': bot}));

  Profile profile({String? displayName}) =>
      Profile(userId: '@ana:pangea.chat', displayName: displayName);

  test('a resolved profile names the user, not their localpart', () {
    expect(
      profileDisplayName(
        '@ana:pangea.chat',
        profile(displayName: 'Ana Ruiz'),
        l10n,
      ),
      'Ana Ruiz',
    );
  });

  test('an unresolved profile falls back to the localpart — the pre-fix look, '
      'now only a placeholder', () {
    expect(profileDisplayName('@ana:pangea.chat', null, l10n), 'ana');
    expect(profileDisplayName('@ana:pangea.chat', profile(), l10n), 'ana');
  });

  test('the bot keeps its localized name, which its English server-side '
      'profile would otherwise override', () {
    expect(
      profileDisplayName(bot, profile(displayName: 'Pangea Bot'), l10n),
      l10n.botDisplayName,
    );
  });
}
