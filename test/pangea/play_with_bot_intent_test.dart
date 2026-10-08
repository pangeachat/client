import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/play_with_bot_intent.dart';

/// The "Play with a bot" choice carried from the start page to the launched
/// session (#9333): read once, per activity, then gone.
void main() {
  tearDown(PlayWithBotIntent.clear);

  test('a set intent is consumed once, then cleared', () {
    PlayWithBotIntent.set('act-1', withBot: true);
    expect(PlayWithBotIntent.consume('act-1'), isTrue);
    expect(PlayWithBotIntent.consume('act-1'), isFalse);
  });

  test('nothing set means no bot', () {
    expect(PlayWithBotIntent.consume('act-1'), isFalse);
  });

  test('intents are kept per activity', () {
    PlayWithBotIntent.set('act-1', withBot: true);
    expect(PlayWithBotIntent.consume('act-2'), isFalse);
    expect(PlayWithBotIntent.consume('act-1'), isTrue);
  });

  test('setting withBot: false clears an earlier intent', () {
    PlayWithBotIntent.set('act-1', withBot: true);
    PlayWithBotIntent.set('act-1', withBot: false);
    expect(PlayWithBotIntent.consume('act-1'), isFalse);
  });

  test('clear forgets every intent', () {
    PlayWithBotIntent.set('act-1', withBot: true);
    PlayWithBotIntent.set('act-2', withBot: true);
    PlayWithBotIntent.clear();
    expect(PlayWithBotIntent.consume('act-1'), isFalse);
    expect(PlayWithBotIntent.consume('act-2'), isFalse);
  });
}
