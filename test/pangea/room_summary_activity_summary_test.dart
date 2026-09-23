import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_summary_room_extension.dart';
import 'package:fluffychat/features/room_summaries/room_summary_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

/// A session's preview reads the same summary slots, in the same order, as
/// the open room: the bot's `canonical` slot, else one an older client wrote,
/// with the analytics from their own slot (#9199).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bot = '@bot:example.org';
  const learner = '@ana:example.org';

  setUpAll(() async {
    dotenv.testLoad(fileInput: 'BOT_NAME=$bot');
    // The bot's name is read through a GetStorage box, which needs
    // path_provider; point it at a temp dir.
    final tempDir = await Directory.systemTemp.createTemp('preview_summary');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
  });

  Map<String, dynamic> slot(String sender, Map<String, dynamic> content) => {
    'sender': sender,
    'content': content,
  };

  Map<String, dynamic> summary(String text) => {
    'summary': {'participants': [], 'summary': text},
  };

  RoomSummaryResponse parse(Map<String, dynamic> slots) =>
      RoomSummaryResponse.fromJson({
        'membership_summary': {learner: 'join'},
        PangeaEventTypes.activitySummary: slots,
      }, l1Code: 'en');

  test('prefers the bot\'s summary over an older client\'s', () {
    final preview = parse({
      ActivitySummaryStateKeys.legacyPreview: slot(learner, summary('Old.')),
      ActivitySummaryStateKeys.canonical: slot(bot, summary('The bot\'s.')),
    });
    expect(preview.activitySummary?.summary?.summary, 'The bot\'s.');
  });

  test('ignores a canonical summary anyone but the bot wrote', () {
    final preview = parse({
      ActivitySummaryStateKeys.canonical: slot(learner, summary('Forged.')),
      'en': slot(learner, summary('Per L1.')),
    });
    expect(preview.activitySummary?.summary?.summary, 'Per L1.');
  });

  test('reads analytics from their own slot, else from an old summary', () {
    Map<String, dynamic> uses(String lemma) => {
      learner: [
        {'lemma': lemma, 'type': 'vocab', 'cat': 'n', 'times_used': 1},
      ],
    };
    String? lemmaOf(RoomSummaryResponse preview) => preview
        .activitySummaryAnalytics
        ?.constructs[learner]
        ?.usages
        .values
        .single
        .identifier
        .lemma;

    final legacy = parse({
      'en': slot(learner, {...summary('Per L1.'), 'analytics': uses('café')}),
    });
    expect(lemmaOf(legacy), 'café');

    final ownSlot = parse({
      ActivitySummaryStateKeys.canonical: slot(bot, summary('The bot\'s.')),
      ActivitySummaryStateKeys.analytics: slot(learner, uses('leche')),
    });
    expect(lemmaOf(ownSlot), 'leche');
  });
}
