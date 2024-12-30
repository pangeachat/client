import 'dart:async';
import 'dart:math';

import 'package:fluffychat/pangea/controllers/get_analytics_controller.dart';
import 'package:fluffychat/pangea/controllers/put_analytics_controller.dart';
import 'package:fluffychat/pangea/utils/bot_style.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';

class PointsGainedAnimation extends StatefulWidget {
  final Color? gainColor;
  final Color? loseColor;
  final AnalyticsUpdateOrigin origin;

  const PointsGainedAnimation({
    super.key,
    required this.origin,
    this.gainColor = Colors.green,
    this.loseColor = Colors.red,
  });

  @override
  PointsGainedAnimationState createState() => PointsGainedAnimationState();
}

class PointsGainedAnimationState extends State<PointsGainedAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _swayAnimation;

  StreamSubscription? _pointsSubscription;
  int? get _prevXP =>
      MatrixState.pangeaController.getAnalytics.constructListModel.prevXP;
  int? get _currentXP =>
      MatrixState.pangeaController.getAnalytics.constructListModel.totalXP;
  int? _addedPoints;

  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0.0, -1.75),
      end: const Offset(0.0, -2.75),
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
      ),
    );

    _fadeAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
      ),
    );

    _swayAnimation = Tween<double>(
      begin: 0.0,
      end: 2 * pi
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.linear,
      ),
    );

    _pointsSubscription = MatrixState
        .pangeaController.getAnalytics.analyticsStream.stream
        .listen(_showPointsGained);
  }

  @override
  void dispose() {
    _controller.dispose();
    _pointsSubscription?.cancel();
    super.dispose();
  }

  void _showPointsGained(AnalyticsStreamUpdate update) {
    if (update.origin != widget.origin) return;
    setState(() => _addedPoints = (_currentXP ?? 0) - (_prevXP ?? 0));
    if (_prevXP != _currentXP) {
      _controller.reset();
      _controller.forward();
    }
  }

  bool get animate =>
      _currentXP != null &&
      _prevXP != null &&
      _addedPoints != null &&
      _prevXP! != _currentXP!;

  @override
  Widget build(BuildContext context) {
    if (!animate) return const SizedBox();

    final textColor = _addedPoints! > 0 ? widget.gainColor  : widget.loseColor;

    return SlideTransition(
      position: _offsetAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: IgnorePointer(
          ignoring: _controller.isAnimating,
          child: Wrap( 
            direction: Axis.horizontal, 
            children: _addedPoints! > 0 ? 
              //If gain, show number of "+"s equal to _addedPoints.
              List.generate(_addedPoints!, (_) {
                final randomOffset = Offset(
                  (_random.nextDouble() - 0.5) * 30,
                  (_random.nextDouble() - 0.5) * 30,
                ); 
                return AnimatedBuilder(
                  animation: _swayAnimation,
                  builder: (context, child){
                    final swayOffsetX = sin(_swayAnimation.value) * 15;
                    return Transform.translate(
                      offset: Offset(swayOffsetX, randomOffset.dy) +
                        randomOffset,
                      child: Text(
                        "+",
                        style: BotStyle.text(
                          context,
                          big: true,
                          setColor: textColor == null,
                          existingStyle: TextStyle(
                            color: textColor,
                        ),
                      ),
                    ),
                  );
                },
              );
            })
          //If loss, just show negative number of points lost.
          : [
              Text(
                '$_addedPoints',
                style: BotStyle.text(
                  context,
                  big: true,
                  setColor: textColor == null,
                  existingStyle: TextStyle(
                    color: textColor,
                  ),
                ),
              ),
            ],
          ), 
        ),
      ),
    );
  }
}
