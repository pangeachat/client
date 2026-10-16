import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';

/// The word webs around the completed stamps in view (under [kStampWordWeb]):
/// each saved activity in [cards] webs out the words [wordsFor] gives it, once
/// the map is zoomed in to [minZoom] or closer.
class StampWordWebLayer extends StatelessWidget {
  /// Closer than a whole-world view, where a Mission's stamps would pile into
  /// each other.
  static const double minZoom = 9.0;

  final List<QuestActivityCard> cards;
  final Set<String> savedActivityIds;
  final List<String> Function(String activityId) wordsFor;

  const StampWordWebLayer({
    required this.cards,
    required this.savedActivityIds,
    required this.wordsFor,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final zoomedIn = MapCamera.of(context).zoom >= minZoom;
    return MarkerLayer(
      markers: [
        if (zoomedIn)
          for (final card in cards)
            if (card.point != null &&
                savedActivityIds.contains(card.activityId))
              for (final words in [wordsFor(card.activityId)])
                if (words.isNotEmpty)
                  Marker(
                    point: card.point!,
                    width: StampWordWeb.width,
                    height: StampWordWeb.height,
                    child: IgnorePointer(
                      child: StampWordWeb(
                        key: ValueKey('words-${card.activityId}'),
                        words: words,
                      ),
                    ),
                  ),
      ],
    );
  }
}

/// The words a saved activity's stamp webs out on the map: light-gold chips
/// around the stamp, each tied to it by a thin gold line, like the words a
/// message gains in chat.
class StampWordWeb extends StatelessWidget {
  final List<String> words;

  const StampWordWeb({required this.words, super.key});

  static const double width = 300.0;
  static const double height = 210.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pangea = theme.pangea;
    const center = Offset(width / 2, height / 2);
    final positions = [
      for (var i = 0; i < words.length; i++)
        center +
            Offset(
              math.cos(-math.pi / 2 + (i + 0.5) * 2 * math.pi / words.length) *
                  (width / 2 - 52),
              math.sin(-math.pi / 2 + (i + 0.5) * 2 * math.pi / words.length) *
                  (height / 2 - 18),
            ),
    ];
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CustomPaint(
            size: const Size(width, height),
            painter: _WordWebPainter(
              center: center,
              ends: positions,
              color: pangea.goldFixedDim,
            ),
          ),
          for (var i = 0; i < words.length; i++)
            Positioned(
              left: positions[i].dx,
              top: positions[i].dy,
              child: FractionalTranslation(
                translation: const Offset(-0.5, -0.5),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: pangea.goldContainer,
                    borderRadius: BorderRadius.circular(999.0),
                    border: Border.all(color: pangea.goldFixedDim, width: 1.5),
                    boxShadow: const [
                      BoxShadow(blurRadius: 2, color: Colors.black26),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8.0,
                      vertical: 2.0,
                    ),
                    child: Text(
                      words[i],
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: pangea.onGoldContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WordWebPainter extends CustomPainter {
  final Offset center;
  final List<Offset> ends;
  final Color color;

  _WordWebPainter({
    required this.center,
    required this.ends,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    for (final end in ends) {
      canvas.drawLine(center, end, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WordWebPainter old) =>
      old.center != center ||
      old.color != color ||
      old.ends.length != ends.length;
}
