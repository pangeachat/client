import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/features/bot/widgets/bot_face_svg.dart';

/// The bot is drawn two ways, animated and as a still, and both have to come
/// from the one asset. Before this, the unanimated surfaces fetched a
/// separately authored PNG over the network, which is how the bot ended up
/// looking like two different characters in one app.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const purple = Color(0xFF8560E0);
  const teal = Color(0xFF0F9E8E);

  Future<List<int>> pixels(ui.Image image) async {
    final data = await image.toByteData();
    return data!.buffer.asUint8List().toList();
  }

  test('the asset is decoded once and shared', () async {
    final first = await BotFaceAssetsAccess.file();
    final second = await BotFaceAssetsAccess.file();
    expect(first, isNotNull, reason: 'the bundled asset must decode');
    expect(
      identical(first, second),
      isTrue,
      reason:
          'every bot face shares one decode; a second is ~3.5ms wasted '
          'and a second native file held open',
    );
  });

  test('a still is drawn for the unanimated surfaces', () async {
    final image = await BotFaceAssetsAccess.still(purple, BotExpression.idle);
    expect(image, isNotNull, reason: 'the still must come from the asset');
    expect(image!.width, greaterThan(0));

    final px = await pixels(image);
    var opaque = 0;
    for (var i = 3; i < px.length; i += 4) {
      if (px[i] > 0) opaque++;
    }
    expect(
      opaque,
      greaterThan(0),
      reason: 'the still must actually contain the bot',
    );
  });

  test('the still is cached per colour and expression', () async {
    final a = await BotFaceAssetsAccess.still(purple, BotExpression.idle);
    final b = await BotFaceAssetsAccess.still(purple, BotExpression.idle);
    expect(
      identical(a, b),
      isTrue,
      reason: 'redrawing the same still per widget defeats the point',
    );
  });

  test('the still follows the colour the animation would use', () async {
    final a = await BotFaceAssetsAccess.still(purple, BotExpression.idle);
    final b = await BotFaceAssetsAccess.still(teal, BotExpression.idle);
    expect(
      identical(a, b),
      isFalse,
      reason: 'a different colour is a different still',
    );
    expect(
      await pixels(a!),
      isNot(equals(await pixels(b!))),
      reason:
          'the still must honour botColor, or an unanimated bot will not '
          'match an animated one beside it',
    );
  });

  test('the still leaves its backdrop clear', () async {
    final image = await BotFaceAssetsAccess.still(purple, BotExpression.idle);
    final px = await pixels(image!);
    var clear = 0;
    for (var i = 3; i < px.length; i += 4) {
      if (px[i] == 0) clear++;
    }
    expect(
      clear / (px.length / 4),
      greaterThan(0.25),
      reason:
          'the still inherits the artboard, so it must not gain the '
          'backdrop the animation does not have',
    );
  });

  test('the bot keeps one colour whatever the theme', () {
    // The whole point of the single source: a learner who recolours the app
    // still sees the same character, and the animated and still faces beside
    // each other cannot disagree.
    expect(
      PangeaColors.of(Brightness.light).botFill,
      equals(PangeaColors.of(Brightness.dark).botFill),
      reason: 'the bot must not change colour between themes',
    );
    expect(
      PangeaColors.of(Brightness.light).botFill,
      equals(PangeaColors.brandKey),
      reason: 'the bot is the brand purple, not a tone of it',
    );
  });
}
