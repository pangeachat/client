import 'dart:ui' show PathMetric;
import 'dart:math';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/enum/instructions_enum.dart';
import 'package:fluffychat/pangea/utils/inline_tooltip.dart';
import 'package:flutter/material.dart';

class StarAnimationWidget extends StatefulWidget {

  const StarAnimationWidget({super.key,});

  @override
  _StarAnimationWidgetState createState() => _StarAnimationWidgetState();
}

class _StarAnimationWidgetState extends State<StarAnimationWidget> with TickerProviderStateMixin {

  late AnimationController _controller;
  late AnimationController _textAnimationController;

  late Animation<double> _starOpacityAnimation;
  late Animation<double> _textOpacityAnimation;
  late Animation<double> _starSizeAnimation;
  late Animation<double> _rotationAnimation;
  late final Animation<double> _textSizeAnimation;
  late final Animation<double> _textColorAnimation;

  late Path _path;
  late PathMetric _pathMetric;


  @override
  void initState() {
    super.initState();

    initAnimationVars();

    //Add .20 sec delay before starting animation so beginning doesn't get cutoff when loading
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        _controller.forward();
      }
    });
  }


  @override
  void dispose() {
    // Dispose of controllers to free resources
    _controller.dispose();
    _textAnimationController.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {

    // Column to stack star and text
    return Stack(
      //mainAxisSize: MainAxisSize.min,
      children: [
        
        // Pertaining to star, go up and off screen while fading (opacity)
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            // Calculate position for star by getting current place on path and its direction (tanforoffset)
            final progress = _controller.value;
            final position = _pathMetric.getTangentForOffset(_pathMetric.length * progress)?.position; 
            
            return Transform.translate(
              offset: position != null ? Offset(position.dx, position.dy-20) : const Offset(0, -20),
              child: 

              Transform.rotate(
                angle: _rotationAnimation.value,
                child: 

                SizedBox(
                  // Set constant height and width for the star container
                  height: 40.0,
                  width: 60.0,
                  child: Center(
                    child: Opacity(
                      opacity: _starOpacityAnimation.value,
                      child: Icon(
                        Icons.star,
                        color: Colors.amber,
                        size: _starSizeAnimation.value,
                      ),
                    ),
                  ),
                ),

              ),

            );
          },
        ),
        
        // Pertaining to the text, scale size and color opacity constantly for effect
        AnimatedBuilder(
          animation: _textAnimationController,
          builder: (context, child) {

            return Opacity(
              opacity: _textOpacityAnimation.value,
              child: Transform.scale(
                scale: _textSizeAnimation.value,
                child: Text(
                'Translated!',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary.withOpacity(_textColorAnimation.value),
                  fontSize: 20,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            );
          },
        ),
      ],
    );
  }


  // Helper to initialize vars for animation
  void initAnimationVars() {

    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500), 
      vsync: this,
    );

    _textAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);

    _starOpacityAnimation = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.8, curve: Curves.easeIn),
      ),
    );

    _textOpacityAnimation = Tween<double>(begin:0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.5, 1.0, curve: Curves.easeIn),
      ),
    );

    _starSizeAnimation = Tween<double>(begin: 80, end: 40).animate(
      CurvedAnimation(
        parent: _controller, 
        curve: const Interval(0.0, 1.0, curve: Curves.easeIn),
      ),
    );

    // 3.5 rotations
    _rotationAnimation = Tween<double>(begin: 0, end: 7 * pi).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.8, curve: Curves.easeIn),
      ),
    );

    _textSizeAnimation = Tween<double>(begin: 1, end: 1.2,).animate(
      CurvedAnimation(
        parent: _textAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    _textColorAnimation = Tween<double>(
      begin: 1,
      end: 0.5)
    .animate(_textAnimationController);

    // Up, left, and down curve
    _path = Path()..quadraticBezierTo(-60, -170, -80, 310); 
    _pathMetric = _path.computeMetrics().first;
  }
}


class GamifiedTextWidget extends StatelessWidget {

  const GamifiedTextWidget({super.key,});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: AppConfig.toolbarMinWidth,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          children: [
            StarAnimationWidget(),
            InlineTooltip(
              instructionsEnum: InstructionsEnum.unlockedLanguageTools,
            ),
          ],
        ),
      ),
    );
  }
}
