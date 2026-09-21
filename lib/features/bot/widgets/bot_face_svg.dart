import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:rive/rive.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';

enum BotExpression { gold, nonGold, addled, idle, surprised }

extension BotExpressionTrigger on BotExpression {
  /// Name of the trigger in the asset's view model that plays this
  /// expression. Every emote holds until `idle` fires again.
  String get trigger {
    switch (this) {
      case BotExpression.gold:
        return 'goldEmote';
      case BotExpression.nonGold:
        return 'nonGoldEmote';
      case BotExpression.surprised:
        return 'surprised';
      case BotExpression.addled:
        return 'addled';
      case BotExpression.idle:
        return 'idle';
    }
  }
}

/// The decoded asset and its rendered resting poses, shared by every bot face.
///
/// A bot face used to decode the asset for itself, at ~3.5ms a time, and any
/// surface that did not want an animation fetched a PNG over the network
/// instead. Both are per-widget costs on a screen that can show a dozen bots,
/// and the PNG was a second, separately authored picture of the same character
/// that could drift from the animation. So the asset is decoded once here, and
/// a still is drawn from that same asset for the surfaces that only need a
/// picture.
class _BotFaceAssets {
  _BotFaceAssets._();

  static const assetPath = 'assets/pangea/bot_faces/pangea_bot_databound.riv';
  static const stateMachineName = 'BotIconStateMachine';
  static const viewModelName = 'BotIconViewModel';

  /// Rendered wide enough to stay crisp on the largest bot face at the highest
  /// device pixel ratio; every use scales down from here.
  static const _stillSize = 256;

  static Future<File?>? _file;
  static final Map<int, Future<ui.Image?>> _stills = {};

  /// Never disposed: one file backs every bot face for the life of the app,
  /// and disposing it would invalidate artboards still on screen.
  static Future<File?> file() {
    return _file ??= () async {
      await RiveNative.init();
      final file = await File.asset(assetPath, riveFactory: Factory.flutter);
      if (file == null) {
        ErrorHandler.logError(
          e: Exception('Failed to decode bot face Rive asset'),
          data: {'asset': assetPath},
          level: SentryLevel.warning,
        );
      }
      return file;
    }();
  }

  /// The resting pose for [colour] and [expression], drawn from the asset.
  ///
  /// Cached per colour and expression, which is a handful of images for the
  /// life of the app. They are deliberately not disposed: they outlive any one
  /// widget and are cheaper to keep than to redraw.
  static Future<ui.Image?> still(Color colour, BotExpression expression) {
    final key = Object.hash(colour.toARGB32(), expression.index);
    return _stills[key] ??= _drawStill(colour, expression);
  }

  static Future<ui.Image?> _drawStill(
    Color colour,
    BotExpression expression,
  ) async {
    final file = await BotFaceAssetsAccess.file();
    if (file == null) return null;
    final artboard = file.defaultArtboard();
    if (artboard == null) return null;
    final machine = artboard.stateMachine(stateMachineName);
    if (machine == null) {
      artboard.dispose();
      return null;
    }

    final viewModel = file
        .viewModelByName(viewModelName)
        ?.createDefaultInstance();
    if (viewModel != null) {
      machine.bindViewModelInstance(viewModel);
      viewModel.color('botColor')?.value = colour;
    }

    // Past the entrance, then far enough into the expression for it to have
    // reached the pose it holds.
    BotFaceState.skipEnter(machine);
    viewModel?.trigger(expression.trigger)?.trigger();
    for (var i = 0; i < 90; i++) {
      machine.advanceAndApply(1 / 60);
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      const Rect.fromLTWH(0, 0, _stillSize * 1.0, _stillSize * 1.0),
    );
    final renderer = Renderer.make(canvas);
    renderer.save();
    renderer.align(
      Fit.cover,
      Alignment.center,
      AABB.fromValues(0, 0, _stillSize * 1.0, _stillSize * 1.0),
      artboard.bounds,
      1.0,
    );
    artboard.draw(renderer);
    renderer.restore();
    final image = await recorder.endRecording().toImage(_stillSize, _stillSize);

    machine.dispose();
    artboard.dispose();
    return image;
  }
}

/// Test seam for the shared file, so a test can assert one decode is shared.
@visibleForTesting
class BotFaceAssetsAccess {
  static Future<File?> file() => _BotFaceAssets.file();
  static Future<ui.Image?> still(Color colour, BotExpression expression) =>
      _BotFaceAssets.still(colour, expression);
}

class BotFace extends StatefulWidget {
  final double width;

  /// Body colour of the bot. Shading follows it automatically, and the eyes
  /// and metal parts stay neutral. Defaults to the brand purple.
  final Color? forceColor;
  final BotExpression expression;

  /// When false, draw the resting pose as a still instead of running the
  /// animation. The picture comes from the same asset, so an unanimated bot
  /// is the same bot. [Avatar] leaves this off for list rows, where a live
  /// state machine per row costs a frame budget for motion nobody is
  /// watching.
  final bool animate;

  const BotFace({
    super.key,
    required this.width,
    required this.expression,
    this.forceColor,
    this.animate = true,
  });

  @override
  BotFaceState createState() => BotFaceState();
}

class BotFaceState extends State<BotFace> {
  /// The artboard plays a one-second Enter animation on load (the bot drops
  /// in), and any trigger fired during it is swallowed rather than queued.
  /// Measured against the asset: a trigger is lost at 60 frames and lands from
  /// 65 (~1.08s). A face that opens idle keeps Enter as its entrance and
  /// re-fires its expression after this delay; any other opening expression
  /// skips Enter, see [skipEnter].
  static const _enterSettle = Duration(milliseconds: 1250);
  static const _frameSeconds = 1 / 60;

  RiveWidgetController? _controller;
  ViewModelInstance? _viewModel;
  Timer? _settleTimer;

  /// True while the asset decodes. Both callers of [_load] are followed by a
  /// build, so it is set without a setState.
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.animate) _load();
  }

  @override
  void didUpdateWidget(BotFace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate) {
      // Avatar flips this per row, so the widget has to be able to drop the
      // animation and pick it back up rather than assuming the first value
      // holds for its lifetime.
      widget.animate ? _load() : _unload();
      return;
    }
    if (!widget.animate) return;
    if (oldWidget.expression != widget.expression) _playExpression();
    if (oldWidget.forceColor != widget.forceColor) _applyColour();
  }

  /// Drop the animation and fall back to the still.
  void _unload() {
    _settleTimer?.cancel();
    _settleTimer = null;
    setState(() {
      _controller?.dispose();
      _controller = null;
      _viewModel = null;
    });
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _loading = true;
    try {
      await _loadAsset();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadAsset() async {
    final file = await BotFaceAssetsAccess.file();
    // The shared loader reports a failed decode once; a face that cannot draw
    // itself falls through to the still, which fails the same way.
    if (file == null) return;

    final controller = RiveWidgetController(
      file,
      stateMachineSelector: const StateMachineNamed(
        _BotFaceAssets.stateMachineName,
      ),
    );

    final viewModel = file
        .viewModelByName(_BotFaceAssets.viewModelName)
        ?.createDefaultInstance();
    if (viewModel == null) {
      // The asset is renderable but not steerable: it will animate on its own
      // and ignore colour and expression. Worth knowing about rather than
      // shipping a bot that silently stops reacting.
      ErrorHandler.logError(
        e: Exception(
          'Bot face Rive asset has no '
          '${_BotFaceAssets.viewModelName} view model',
        ),
        data: {'asset': _BotFaceAssets.assetPath},
        level: SentryLevel.warning,
      );
    } else {
      controller.stateMachine.bindViewModelInstance(viewModel);
    }

    // `animate` can have been turned off while the asset was decoding, so a
    // late load must not install a controller the widget no longer wants.
    if (!mounted || !widget.animate) {
      controller.dispose();
      return;
    }

    setState(() {
      _controller?.dispose();
      _controller = controller;
      _viewModel = viewModel;
    });

    _applyColour();
    _settleTimer?.cancel();
    if (widget.expression == BotExpression.idle) {
      // Enter ends in idle on its own. The re-fire is for an expression that
      // changes while Enter is still swallowing triggers.
      _settleTimer = Timer(_enterSettle, () {
        if (mounted) _playExpression();
      });
      return;
    }
    // Otherwise the bot drops in wearing its resting face and only changes a
    // second later, which reads as a glitch on a dialog that opens addled.
    skipEnter(controller.stateMachine);
    _playExpression();
    // Addled swaps on the next frame, so taking that frame now makes it the
    // first one painted. The other emotes ease in from the resting pose.
    controller.advance(_frameSeconds);
  }

  /// Runs [machine] through Enter, so the next trigger lands. Stepped a frame
  /// at a time because one large advance leaves the machine mid-Enter with
  /// the bot undrawn.
  @visibleForTesting
  static void skipEnter(StateMachine machine) {
    final frames = _enterSettle.inMicroseconds / 1e6 / _frameSeconds;
    for (var i = 0; i < frames; i++) {
      machine.advanceAndApply(_frameSeconds);
    }
  }

  /// The bot wears the learner's chosen colour, the same `primary` the
  /// language chip beside it uses, so the two read as one palette rather than
  /// a themed app with a purple mascot dropped into it. Both the animation
  /// and the still resolve the colour here, so the two cannot disagree.
  Color _colour(BuildContext context) =>
      widget.forceColor ?? Theme.of(context).colorScheme.primary;

  void _applyColour() {
    final viewModel = _viewModel;
    if (viewModel == null) return;
    // Set rather than read: the Rive view model holds the value.
    viewModel.color('botColor')?.value = _colour(context);
  }

  void _playExpression() {
    _viewModel?.trigger(widget.expression.trigger)?.trigger();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.width,
      child: widget.animate ? _animated(context) : _still(context),
    );
  }

  Widget _animated(BuildContext context) {
    final controller = _controller;
    if (controller != null) {
      return RiveWidget(controller: controller, fit: Fit.cover);
    }
    // A face about to open on an emote waits out the decode empty rather than
    // flash the resting face and swap a moment later.
    if (_loading && widget.expression != BotExpression.idle) {
      return const SizedBox.shrink();
    }
    return _still(context);
  }

  Widget _still(BuildContext context) {
    return FutureBuilder<ui.Image?>(
      future: BotFaceAssetsAccess.still(_colour(context), widget.expression),
      builder: (context, snapshot) {
        final image = snapshot.data;
        if (image == null) return const SizedBox.shrink();
        return RawImage(
          image: image,
          width: widget.width,
          height: widget.width,
          fit: BoxFit.cover,
        );
      },
    );
  }
}
