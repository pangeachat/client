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
  List<Animation<double>> _swayAnimation = [];
  List<double> _randomSwayOffset = [];
  List<Offset> _particleTrajectories = [];

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
      duration: const Duration(seconds: 5),
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

    _pointsSubscription = MatrixState
        .pangeaController.getAnalytics.analyticsStream.stream
        .listen(_showPointsGained);
  }

  void initParticleTrajectories() {
  _particleTrajectories.clear();
  for (int i = 0; i < (_addedPoints ?? 0); i++) {
    final angle = _random.nextDouble() * (pi / 2) + pi / 4; // Random angle in the V-shaped range.
    final baseSpeed = 20; // Initial base speed.
    final exponentialFactor = 30; // Factor for exponential growth.
    final speedMultiplier = _random.nextDouble(); // Random speed multiplier.
    final speed = baseSpeed * pow(exponentialFactor, speedMultiplier); // Exponential speed.
    _particleTrajectories.add(Offset(speed * cos(angle), -speed * sin(angle)));
    }
  }

  void initSwayAnimations(){
    _swayAnimation.clear();
    _randomSwayOffset.clear();
    initParticleTrajectories();

    for(int i = 0; i < (_addedPoints ?? 0); i++) {
      _swayAnimation.add(
        Tween<double>(
          begin: 0.0,
          end: 2 * pi,
        ).animate(
          CurvedAnimation(
            parent: _controller,
            curve: Curves.linear,
          ),
        ),
      );
      _randomSwayOffset.add(_random.nextDouble() * 2 * pi);
    }
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
      initSwayAnimations();
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
          child: Stack( 
            children: _addedPoints! > 0 ? 
              //If gain, show number of "+"s equal to _addedPoints.
              List.generate(_addedPoints!, (index) {
                return AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child){
                    final progress = _controller.value; 
                    final trajectory = _particleTrajectories[index];
                    final swayOffsetX = sin(_swayAnimation[index].value + _randomSwayOffset[index]) * 5;
                    return Transform.translate(
                      offset: Offset(
                        trajectory.dx * pow(progress, 2),
                        trajectory.dy * pow(progress, 2),
                      ),
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
