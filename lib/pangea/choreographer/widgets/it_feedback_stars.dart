import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/choreographer/widgets/choice_animation.dart';

class FillingStars extends StatefulWidget {
  final int rating;
  const FillingStars({
    super.key,
    required this.rating,
  });

  @override
  State<FillingStars> createState() => _FillingStarsState();
}

class _FillingStarsState extends State<FillingStars> {
  late List<bool> _isFilledList;
  int _lastRating = 0;

  @override
  void initState() {
    super.initState();
    // Initialize with all stars unfilled
    _isFilledList = List.filled(5, false);
    // Start animation after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _lastRating = widget.rating;
      _animate();
    });
  }

  @override
  void didUpdateWidget(FillingStars oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the rating changes, update the animation
    if (oldWidget.rating != widget.rating) {
      // Reset if the rating decreases
      if (widget.rating < _lastRating) {
        _isFilledList = List.filled(5, false);
      }
      _lastRating = widget.rating;
      _animate();
    }
  }

  Future<void> _animate() async {
    // Only animate unfilled stars up to the target rating
    for (int i = 0; i < widget.rating; i++) {
      if (!_isFilledList[i]) {
        await Future.delayed(
            const Duration(milliseconds: choiceArrayAnimationDuration), () {
          if (mounted) {
            setState(() => _isFilledList[i] = true);
          }
        });
      }
    }

    // Also handle the case where rating decreases by unfilling stars
    for (int i = widget.rating; i < 5; i++) {
      if (_isFilledList[i]) {
        setState(() => _isFilledList[i] = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: choiceArrayAnimationDuration),
          transitionBuilder: (Widget child, Animation<double> animation) {
            return ScaleTransition(
              scale: animation,
              child: child,
            );
          },
          child: Icon(
            _isFilledList[index] ? Icons.star_rounded : Icons.star_rounded,
            key: ValueKey<bool>(_isFilledList[index]),
            color: _isFilledList[index]
                ? AppConfig.gold
                : Theme.of(context).cardColor.withAlpha(180),
            size: 32.0,
          ),
        );
      }),
    );
  }
}
