import 'dart:async';

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

  /// The artboard plays a one-second Enter animation on load, and any trigger
  /// fired during it is swallowed rather than queued. Measured against the
  /// asset: a trigger is lost at 60 frames and lands from 65 (~1.08s). So the
  /// opening expression is fired twice, once immediately in case the machine
  /// is already past Enter, and once after this delay.
  static const _enterSettle = Duration(milliseconds: 1250);

  File? _file;
  RiveWidgetController? _controller;
  ViewModelInstance? _viewModel;
  Timer? _settleTimer;

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
    if (oldWidget.expression != widget.expression) _playExpression();
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
    _controller?.dispose();
    _file?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
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
    _playExpression();
    _settleTimer?.cancel();
    _settleTimer = Timer(_enterSettle, () {
      if (mounted) _playExpression();
    });
  }

  void _applyColour() {
    final viewModel = _viewModel;
    if (viewModel == null) return;
    // The brand fill, from the theme: the seed purple in light and the
    // scheme's lighter cut of it in dark. Re-applied when the theme changes
    // (didChangeDependencies), since the Rive view model holds a value.
    viewModel.color('botColor')?.value =
        widget.forceColor ?? Theme.of(context).colorScheme.primaryContainer;
    // The bot is drawn over dialogs, list rows and the map, so its own
    // backdrop has to be clear. The asset defaults this to opaque white.
    viewModel.color('backgroundColor')?.value = Colors.transparent;
  }

  void _playExpression() {
    _viewModel?.trigger(widget.expression.trigger)?.trigger();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return SizedBox(
      width: widget.width,
      height: widget.width,
      child: controller != null
          ? RiveWidget(controller: controller, fit: Fit.cover)
          : CachedNetworkImage(
              imageUrl: '${AppConfig.assetsBaseURL}/bot_face_neutral.png',
              placeholder: (context, url) =>
                  const CircularProgressIndicator.adaptive(),
              errorWidget: (context, url, error) => const Icon(Icons.error),
            ),
    );
  }
}
