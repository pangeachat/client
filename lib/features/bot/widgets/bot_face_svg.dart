import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:rive/rive.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/config/app_config.dart';
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

class BotFace extends StatefulWidget {
  final double width;

  /// Body colour of the bot. Shading follows it automatically, and the eyes
  /// and metal parts stay neutral. Defaults to the brand purple.
  final Color? forceColor;
  final BotExpression expression;

  /// When false, render the static fallback image instead of the animation.
  /// [Avatar] uses this for list rows, where a live animation per row is not
  /// worth the cost.
  final bool useRive;

  const BotFace({
    super.key,
    required this.width,
    required this.expression,
    this.forceColor,
    this.useRive = true,
  });

  @override
  BotFaceState createState() => BotFaceState();
}

class BotFaceState extends State<BotFace> {
  static const _assetPath = 'assets/pangea/bot_faces/pangea_bot_databound.riv';
  static const _stateMachineName = 'BotIconStateMachine';
  static const _viewModelName = 'BotIconViewModel';

  /// The artboard plays a one-second Enter animation on load (the bot drops
  /// in), and any trigger fired during it is swallowed rather than queued.
  /// Measured against the asset: a trigger is lost at 60 frames and lands from
  /// 65 (~1.08s). A face that opens idle keeps Enter as its entrance and
  /// re-fires its expression after this delay; any other opening expression
  /// skips Enter, see [skipEnter].
  static const _enterSettle = Duration(milliseconds: 1250);
  static const _frameSeconds = 1 / 60;

  /// On web, how long a face animates after it loads or changes expression
  /// before it holds its current frame. Rive's web renderer leaks CanvasKit
  /// memory on every animated frame, so a face left animating filled the
  /// 2 GiB heap in under an hour and aborted the tab (#9286, CLIENT-EWG).
  /// Long enough for Enter, the idle re-fire at [_enterSettle], and the
  /// emote to land.
  static const _webAnimateFor = Duration(seconds: 3);

  File? _file;
  RiveWidgetController? _controller;
  ViewModelInstance? _viewModel;
  Timer? _settleTimer;
  Timer? _holdTimer;

  /// True while the asset decodes. Both callers of [_load] are followed by a
  /// build, so it is set without a setState.
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.useRive) _load();
  }

  @override
  void didUpdateWidget(BotFace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.useRive != widget.useRive) {
      // Avatar flips this per row, so the widget has to be able to drop the
      // animation and pick it back up rather than assuming the first value
      // holds for its lifetime.
      widget.useRive ? _load() : _unload();
      return;
    }
    if (!widget.useRive) return;
    if (oldWidget.expression != widget.expression) {
      _animateBriefly();
      _playExpression();
    }
    if (oldWidget.forceColor != widget.forceColor) _applyColour();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _applyColour();
  }

  /// Drop the animation and fall back to the static image.
  void _unload() {
    _settleTimer?.cancel();
    _settleTimer = null;
    _holdTimer?.cancel();
    _holdTimer = null;
    setState(() {
      _controller?.dispose();
      _file?.dispose();
      _controller = null;
      _file = null;
      _viewModel = null;
    });
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    _holdTimer?.cancel();
    _controller?.dispose();
    _file?.dispose();
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
    await RiveNative.init();
    final file = await File.asset(_assetPath, riveFactory: Factory.flutter);
    if (file == null) {
      ErrorHandler.logError(
        e: Exception('Failed to decode bot face Rive asset'),
        data: {'asset': _assetPath},
        level: SentryLevel.warning,
      );
      return;
    }

    final controller = RiveWidgetController(
      file,
      stateMachineSelector: const StateMachineNamed(_stateMachineName),
    );

    final viewModel = file
        .viewModelByName(_viewModelName)
        ?.createDefaultInstance();
    if (viewModel == null) {
      // The asset is renderable but not steerable: it will animate on its own
      // and ignore colour and expression. Worth knowing about rather than
      // shipping a bot that silently stops reacting.
      ErrorHandler.logError(
        e: Exception('Bot face Rive asset has no $_viewModelName view model'),
        data: {'asset': _assetPath},
        level: SentryLevel.warning,
      );
    } else {
      controller.stateMachine.bindViewModelInstance(viewModel);
    }

    // `useRive` can have been turned off while the asset was decoding, so a
    // late load must not install a controller the widget no longer wants.
    if (!mounted || !widget.useRive) {
      controller.dispose();
      file.dispose();
      return;
    }

    setState(() {
      _controller?.dispose();
      _file?.dispose();
      _file = file;
      _controller = controller;
      _viewModel = viewModel;
    });

    _applyColour();
    _animateBriefly();
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

  void _applyColour() {
    final viewModel = _viewModel;
    if (viewModel == null) return;
    // The brand fill, from the theme: the seed purple in light and the
    // scheme's lighter cut of it in dark. Re-applied when the theme changes
    // (didChangeDependencies), since the Rive view model holds a value.
    viewModel.color('botColor')?.value =
        widget.forceColor ?? Theme.of(context).colorScheme.primaryContainer;
  }

  void _playExpression() {
    _viewModel?.trigger(widget.expression.trigger)?.trigger();
  }

  /// On web, lets the face animate for [_webAnimateFor], then holds its
  /// current frame. An inactive controller stops its ticker but still paints,
  /// so the face stays drawn; colour changes land on the next repaint.
  void _animateBriefly() {
    final controller = _controller;
    if (!kIsWeb || controller == null) return;
    controller.active = true;
    _holdTimer?.cancel();
    _holdTimer = Timer(_webAnimateFor, () {
      if (mounted) _controller?.active = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return SizedBox(
      width: widget.width,
      height: widget.width,
      child: controller != null
          ? RiveWidget(controller: controller, fit: Fit.cover)
          // The fallback image is the resting face. A bot about to open on an
          // emote waits out the decode empty rather than flash the wrong face.
          : _loading && widget.expression != BotExpression.idle
          ? null
          : CachedNetworkImage(
              imageUrl: '${AppConfig.assetsBaseURL}/bot_face_neutral.png',
              placeholder: (context, url) =>
                  const CircularProgressIndicator.adaptive(),
              errorWidget: (context, url, error) => const Icon(Icons.error),
            ),
    );
  }
}
