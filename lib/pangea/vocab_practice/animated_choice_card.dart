import 'package:fluffychat/config/app_config.dart';
import 'package:flutter/material.dart';

class AnimatedChoiceCard extends StatefulWidget {
  final String choice;
  final String? emoji;
  final String? altText;
  final VoidCallback onPressed;
  final bool isCorrect;
  final double height;

  const AnimatedChoiceCard({
    required this.choice,
    this.emoji,
    this.altText,
    required this.onPressed,
    required this.isCorrect,
    this.height = 72.0,
    super.key,
  });

  @override
  State<AnimatedChoiceCard> createState() => AnimatedChoiceCardState();
}

class AnimatedChoiceCardState extends State<AnimatedChoiceCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  bool _flipped = false;
  bool _isHovered = false;
  String _textContent = '';

  @override
  void initState() {
    super.initState();
    _textContent = widget.choice;
    _controller = AnimationController(
      duration: const Duration(milliseconds: 220),
      vsync: this,
    );

    _scaleAnim = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _controller.addListener(_onAnimationUpdate);
  }

  void _onAnimationUpdate() {
    //Change text when card is fully shrunk
    if (_controller.value >= 0.95 && !_flipped) {
      setState(() {
        // Replace the text with provided alt text (or keep the original if none provided)
        _textContent = widget.altText ?? widget.choice;
        _flipped = true;
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onAnimationUpdate);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (_flipped) return;

    //Animate forward (shrink), then reverse (expand)
    await _controller.forward();
    await _controller.reverse();

    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    final Color baseColor = colorScheme.surfaceContainerHighest;
    final Color hoverColor = colorScheme.onSurface.withValues(alpha: 0.08);
    final Color tintColor = widget.isCorrect
        ? AppConfig.success.withValues(alpha: 0.3)
        : AppConfig.error.withValues(alpha: 0.3);

    final double baseHeight = widget.height;
    final double baseTextSize =
        (Theme.of(context).textTheme.titleMedium?.fontSize ?? 16) *
            (baseHeight / 72.0).clamp(1.0, 1.4);
    final double emojiSize = baseTextSize * 1.2;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: SizedBox(
        width: double.infinity,
        height: baseHeight,
        child: GestureDetector(
          onTap: _handleTap,
          child: AnimatedBuilder(
            animation: _scaleAnim,
            builder: (context, child) {
              //Hide text when card is very small
              final bool showText = _scaleAnim.value > 0.1;

              return Transform.scale(
                scaleY: _scaleAnim.value,
                child: Container(
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  foregroundDecoration: BoxDecoration(
                    color: _flipped
                        ? tintColor
                        : (_isHovered ? hoverColor : Colors.transparent),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  margin:
                      const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  height: baseHeight,
                  alignment: Alignment.center,
                  child: Opacity(
                    opacity: showText ? 1.0 : 0.0,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (widget.emoji != null && widget.emoji!.isNotEmpty)
                          SizedBox(
                            width: baseHeight,
                            height: baseHeight,
                            child: Center(
                              child: Text(
                                widget.emoji!,
                                style: TextStyle(fontSize: emojiSize),
                              ),
                            ),
                          ),
                        Expanded(
                          child: Text(
                            _textContent,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                            textAlign: TextAlign.left,
                            style: TextStyle(
                              fontSize: baseTextSize,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
