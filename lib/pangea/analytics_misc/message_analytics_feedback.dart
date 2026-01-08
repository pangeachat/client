import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_misc/analytics_navigation_util.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/constructs/construct_level_enum.dart';
import 'package:flutter/material.dart';

class MessageAnalyticsFeedback extends StatefulWidget {
  final int newGrammarConstructs;
  final int newVocabConstructs;
  final int newGreensConstructs;
  final int newFlowersConstructs;
  final VoidCallback close;

  const MessageAnalyticsFeedback({
    required this.newGrammarConstructs,
    required this.newVocabConstructs,
    required this.newGreensConstructs,
    required this.newFlowersConstructs,
    required this.close,
    super.key,
  });

  @override
  State<MessageAnalyticsFeedback> createState() =>
      MessageAnalyticsFeedbackState();
}

class MessageAnalyticsFeedbackState extends State<MessageAnalyticsFeedback>
    with TickerProviderStateMixin {
  late AnimationController _numbersController;
  late AnimationController _bubbleController;
  late AnimationController _tickerController;

  late Animation<double> _numbersOpacityAnimation;
  late Animation<double> _bubbleScaleAnimation;
  late Animation<double> _bubbleOpacityAnimation;

  Animation<int>? _grammarTickerAnimation;
  Animation<int>? _vocabTickerAnimation;
  Animation<int>? _greensTickerAnimation;
  Animation<int>? _flowersTickerAnimation;

  @override
  void initState() {
    super.initState();
    _numbersController = AnimationController(
      vsync: this,
      duration: FluffyThemes.animationDuration,
    );

    _numbersOpacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _numbersController, curve: Curves.easeInOut),
    );

    _bubbleController = AnimationController(
      vsync: this,
      duration: FluffyThemes.animationDuration,
    );

    _bubbleScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _bubbleController, curve: Curves.easeInOut),
    );

    _bubbleOpacityAnimation = Tween<double>(begin: 0.0, end: 0.9).animate(
      CurvedAnimation(parent: _bubbleController, curve: Curves.easeInOut),
    );

    _tickerController = AnimationController(
      vsync: this,
      duration: FluffyThemes.animationDuration,
    );

    _numbersOpacityAnimation.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _startTickerAnimations();
      }
    });

    _bubbleController.forward();
    Future.delayed(
      const Duration(milliseconds: 400),
      _numbersController.forward,
    );
    Future.delayed(const Duration(milliseconds: 4000), () async {
      if (mounted) {
        await _bubbleController.reverse();
        widget.close();
      }
    });
  }

  @override
  void dispose() {
    _numbersController.dispose();
    _bubbleController.dispose();
    _tickerController.dispose();
    super.dispose();
  }

  void _startTickerAnimations() {
    _vocabTickerAnimation = IntTween(
      begin: 0,
      end: widget.newVocabConstructs,
    ).animate(
      CurvedAnimation(
        parent: _tickerController,
        curve: Curves.easeOutCubic,
      ),
    );

    _grammarTickerAnimation = IntTween(
      begin: 0,
      end: widget.newGrammarConstructs,
    ).animate(
      CurvedAnimation(
        parent: _tickerController,
        curve: Curves.easeOutCubic,
      ),
    );

    _greensTickerAnimation = IntTween(
      begin: 0,
      end: widget.newGreensConstructs,
    ).animate(
      CurvedAnimation(
        parent: _tickerController,
        curve: Curves.easeOutCubic,
      ),
    );

    _flowersTickerAnimation = IntTween(
      begin: 0,
      end: widget.newFlowersConstructs,
    ).animate(
      CurvedAnimation(
        parent: _tickerController,
        curve: Curves.easeOutCubic,
      ),
    );

    setState(() {});
    _tickerController.forward();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.newVocabConstructs <= 0 &&
        widget.newGrammarConstructs <= 0 &&
        widget.newGreensConstructs <= 0 &&
        widget.newFlowersConstructs <= 0) {
      return const SizedBox.shrink();
    }

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () =>
            AnalyticsNavigationUtil.navigateToAnalytics(context: context),
        child: ScaleTransition(
          scale: _bubbleScaleAnimation,
          alignment: Alignment.bottomRight,
          child: AnimatedBuilder(
            animation: _bubbleController,
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withAlpha((_bubbleOpacityAnimation.value * 255).round()),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16.0),
                    topRight: Radius.circular(16.0),
                    bottomLeft: Radius.circular(16.0),
                    bottomRight: Radius.circular(4.0),
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: 8.0,
                  horizontal: 16.0,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.newVocabConstructs > 0)
                      _NewConstructsBadge(
                        opacityAnimation: _numbersOpacityAnimation,
                        tickerAnimation: _vocabTickerAnimation,
                        type: ConstructTypeEnum.vocab,
                        tooltip: L10n.of(context).newVocab,
                      ),
                    if (widget.newGrammarConstructs > 0)
                      _NewConstructsBadge(
                        opacityAnimation: _numbersOpacityAnimation,
                        tickerAnimation: _grammarTickerAnimation,
                        type: ConstructTypeEnum.morph,
                        tooltip: L10n.of(context).newGrammar,
                      ),
                    if (widget.newGreensConstructs > 0)
                      _NewConstructsLevelBadge(
                        opacityAnimation: _numbersOpacityAnimation,
                        tickerAnimation: _greensTickerAnimation,
                        level: ConstructLevelEnum.greens,
                        tooltip: "New Greens",
                      ),
                    if (widget.newFlowersConstructs > 0)
                      _NewConstructsLevelBadge(
                        opacityAnimation: _numbersOpacityAnimation,
                        tickerAnimation: _flowersTickerAnimation,
                        level: ConstructLevelEnum.flowers,
                        tooltip: "New Flowers",
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NewConstructsBadge extends StatelessWidget {
  final Animation<double> opacityAnimation;
  final Animation<int>? tickerAnimation;
  final ConstructTypeEnum type;
  final String tooltip;

  const _NewConstructsBadge({
    required this.opacityAnimation,
    required this.tickerAnimation,
    required this.type,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => AnalyticsNavigationUtil.navigateToAnalytics(
        context: context,
        view: type.indicator,
      ),
      child: Tooltip(
        message: tooltip,
        child: AnimatedBuilder(
          animation: opacityAnimation,
          builder: (context, child) {
            return Opacity(
              opacity: opacityAnimation.value,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      type.indicator.icon,
                      color: type.indicator.color(context),
                      size: 24,
                    ),
                    const SizedBox(width: 4.0),
                    _AnimatedCounter(
                      key: ValueKey("$type-counter"),
                      animation: tickerAnimation,
                      style: TextStyle(
                        color: type.indicator.color(context),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NewConstructsLevelBadge extends StatelessWidget {
  final Animation<double> opacityAnimation;
  final Animation<int>? tickerAnimation;
  final ConstructLevelEnum level;
  final String tooltip;

  const _NewConstructsLevelBadge({
    required this.opacityAnimation,
    required this.tickerAnimation,
    required this.level,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => AnalyticsNavigationUtil.navigateToAnalytics(
        context: context,
      ),
      child: Tooltip(
        message: tooltip,
        child: AnimatedBuilder(
          animation: opacityAnimation,
          builder: (context, child) {
            return Opacity(
              opacity: opacityAnimation.value,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    level.icon(24),
                    const SizedBox(width: 4.0),
                    _AnimatedCounter(
                      key: ValueKey("$level-counter"),
                      animation: tickerAnimation,
                      style: TextStyle(
                        color: ConstructTypeEnum.vocab.indicator.color(context),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AnimatedCounter extends StatelessWidget {
  final Animation<int>? animation;
  final TextStyle? style;

  const _AnimatedCounter({
    super.key,
    required this.animation,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    if (animation == null) {
      return Text(
        "+ 0",
        style: style,
      );
    }

    return AnimatedBuilder(
      animation: animation!,
      builder: (context, child) {
        return Text(
          "+ ${animation!.value}",
          style: style,
        );
      },
    );
  }
}
