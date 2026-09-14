import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:rive/rive.dart';

import 'package:fluffychat/features/bot/widgets/bot_face_svg.dart';

/// Guards the contract between [BotFace] and the Rive asset it drives.
///
/// These assert the asset, not the widget tree: a [RiveWidget] never settles
/// under `flutter test`, so pumping one hangs until the suite times out.
/// Rendering the artboard straight to a canvas exercises the same runtime.
const _assetPath = 'assets/pangea/bot_faces/pangea_bot.riv';
const _stateMachineName = 'BotIconStateMachine';
const _viewModelName = 'BotIconViewModel';

/// Frames to advance past the artboard's Enter animation, which swallows any
/// trigger fired during it. Measured: lost at 60 frames, lands from 65.
const _settleFrames = 75;

Future<ui.Image> _render(Artboard artboard, {double size = 120}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));
  final renderer = Renderer.make(canvas);
  renderer.save();
  renderer.align(
    Fit.contain,
    Alignment.center,
    AABB.fromValues(0, 0, size, size),
    artboard.bounds,
    1.0,
  );
  artboard.draw(renderer);
  renderer.restore();
  return recorder.endRecording().toImage(size.toInt(), size.toInt());
}

Future<List<int>> _pixels(ui.Image image) async {
  final data = await image.toByteData();
  return data!.buffer.asUint8List().toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late File file;

  setUpAll(() async {
    await RiveNative.init();
    final loaded = await File.asset(_assetPath, riveFactory: Factory.flutter);
    expect(loaded, isNotNull, reason: '$_assetPath must decode');
    file = loaded!;
  });

  tearDownAll(() => file.dispose());

  test('asset exposes the view model the widget binds to', () {
    final viewModel = file.viewModelByName(_viewModelName);
    expect(viewModel, isNotNull, reason: 'BotFace binds $_viewModelName');
    final names = viewModel!.properties.map((p) => p.name).toSet();
    expect(names, containsAll(['botColor', 'backgroundColor']));
  });

  test('backgroundColor drives the render', () async {
    Future<List<int>> renderWithBackdrop(Color backdrop) async {
      final artboard = file.artboard('BotIconArtboard')!;
      final machine = artboard.stateMachine(_stateMachineName)!;
      final viewModel = file
          .viewModelByName(_viewModelName)!
          .createDefaultInstance()!;
      machine.bindViewModelInstance(viewModel);
      viewModel.color('botColor')!.value = const Color(0xFF8560E0);
      viewModel.color('backgroundColor')!.value = backdrop;
      for (var i = 0; i < _settleFrames; i++) {
        machine.advanceAndApply(1 / 60);
      }
      final pixels = await _pixels(await _render(artboard));
      machine.dispose();
      return pixels;
    }

    // The widget binds this to transparent. The asset ships it opaque white,
    // so if the binding stops reaching the artboard every bot face gains a
    // white box behind it and nothing else would catch that.
    expect(
      await renderWithBackdrop(Colors.transparent),
      isNot(equals(await renderWithBackdrop(const Color(0xFFFFFFFF)))),
      reason: 'binding backgroundColor must change what is drawn',
    );
  });

  test('every BotExpression maps to a trigger that exists in the asset', () {
    final names = file
        .viewModelByName(_viewModelName)!
        .properties
        .map((p) => p.name)
        .toSet();
    for (final expression in BotExpression.values) {
      expect(
        names,
        contains(expression.trigger),
        reason:
            '$expression maps to "${expression.trigger}", missing from the asset',
      );
    }
  });

  test('botColor drives the render', () async {
    Future<List<int>> renderAt(Color color) async {
      final artboard = file.artboard('BotIconArtboard')!;
      final machine = artboard.stateMachine(_stateMachineName)!;
      final viewModel = file
          .viewModelByName(_viewModelName)!
          .createDefaultInstance()!;
      machine.bindViewModelInstance(viewModel);
      viewModel.color('botColor')!.value = color;
      for (var i = 0; i < _settleFrames; i++) {
        machine.advanceAndApply(1 / 60);
      }
      final pixels = await _pixels(await _render(artboard));
      machine.dispose();
      return pixels;
    }

    final purple = await renderAt(const Color(0xFF8560E0));
    final teal = await renderAt(const Color(0xFF0F9E8E));
    expect(
      purple,
      isNot(equals(teal)),
      reason: 'binding botColor must change what is drawn',
    );
  });

  test(
    'each expression trigger changes the render once Enter has finished',
    () async {
      Future<List<int>> renderExpression(BotExpression? expression) async {
        final artboard = file.artboard('BotIconArtboard')!;
        final machine = artboard.stateMachine(_stateMachineName)!;
        final viewModel = file
            .viewModelByName(_viewModelName)!
            .createDefaultInstance()!;
        machine.bindViewModelInstance(viewModel);
        for (var i = 0; i < _settleFrames; i++) {
          machine.advanceAndApply(1 / 60);
        }
        if (expression != null) {
          viewModel.trigger(expression.trigger)!.trigger();
        }
        for (var i = 0; i < 90; i++) {
          machine.advanceAndApply(1 / 60);
        }
        final pixels = await _pixels(await _render(artboard));
        machine.dispose();
        return pixels;
      }

      final untriggered = await renderExpression(null);
      for (final expression in BotExpression.values.where(
        (e) => e != BotExpression.idle,
      )) {
        expect(
          await renderExpression(expression),
          isNot(equals(untriggered)),
          reason: '${expression.trigger} must visibly change the artboard',
        );
      }
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  test(
    'idle releases an emote that is holding',
    () async {
      final artboard = file.artboard('BotIconArtboard')!;
      final machine = artboard.stateMachine(_stateMachineName)!;
      final viewModel = file
          .viewModelByName(_viewModelName)!
          .createDefaultInstance()!;
      machine.bindViewModelInstance(viewModel);
      for (var i = 0; i < _settleFrames; i++) {
        machine.advanceAndApply(1 / 60);
      }

      viewModel.trigger(BotExpression.addled.trigger)!.trigger();
      for (var i = 0; i < 90; i++) {
        machine.advanceAndApply(1 / 60);
      }
      final holding = await _pixels(await _render(artboard));

      // Emotes carry no exit of their own; idle is the only way back. If that
      // stops working the bot sticks on whichever face it last showed.
      viewModel.trigger(BotExpression.idle.trigger)!.trigger();
      for (var i = 0; i < 90; i++) {
        machine.advanceAndApply(1 / 60);
      }
      final released = await _pixels(await _render(artboard));

      expect(
        released,
        isNot(equals(holding)),
        reason: 'firing idle must move the artboard off the held emote',
      );
      machine.dispose();
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );
}
