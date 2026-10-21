import 'package:flutter/material.dart';

import 'package:intl/intl.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/compact_count.dart';

/// The completed mark: a gold coin with a double ring and a check in dark ink,
/// in the theme's golds — the same symbol on an activity's card and its map
/// pin. With a tab — the learner's total XP from the activity when [xp] is
/// given (#9559), else "×N" once they have finished it more than once — the
/// coin and the tab's gold text sit on a see-through pill, light or dark with
/// the theme, for the photo it rides.
class CompletedStamp extends StatelessWidget {
  final double size;
  final int times;

  /// The learner's total XP from every finished session of the activity;
  /// above zero it takes the tab, abbreviated ("1.2K XP").
  final int xp;

  const CompletedStamp({
    required this.size,
    this.times = 1,
    this.xp = 0,
    super.key,
  });

  /// The coin's disc (#9559): the bright fixed gold in both themes.
  static Color paperOf(ThemeData theme) => theme.pangea.goldFixedDim;

  /// The coin's rings and check: the fixed gold's own ink, about 10:1 on
  /// the disc in both themes.
  static Color inkOf(ThemeData theme) => theme.pangea.onGoldFixed;

  /// The tab's see-through pill, for the photo it rides: the surface in
  /// light, the scrim in dark. Each alpha is the lightest touch that keeps
  /// the tab's `gold` text at 4.5:1 over any photo — 90% surface keeps the
  /// light T40 gold at 5.2:1 over a black photo, 72% scrim the dark T80 gold
  /// at 5.4:1 over a white one.
  static Color scrimOf(ThemeData theme) => theme.brightness == Brightness.light
      ? theme.colorScheme.surface.withValues(alpha: 0.9)
      : theme.colorScheme.scrim.withValues(alpha: 0.72);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final completed = times > 1
        ? l10n.completedTimes(times)
        : l10n.activityCompleted;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final label = xp > 0
        ? l10n.activityCompletedWithXp(
            completed,
            NumberFormat.decimalPattern(locale).format(xp),
          )
        : completed;
    final tab = xp > 0
        // The same short count the analytics cluster uses: narrow in every
        // locale, and floored so it never overstates.
        ? l10n.activityXpStamp(compactCount(xp))
        : times > 1
        ? '×$times'
        : null;
    final coin = CustomPaint(
      size: Size.square(size),
      painter: _CompletedStampPainter(ink: inkOf(theme), paper: paperOf(theme)),
    );
    if (tab == null) {
      return Semantics(
        label: label,
        child: ExcludeSemantics(
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 3.0,
                  offset: const Offset(0, 1.5),
                ),
              ],
            ),
            child: coin,
          ),
        ),
      );
    }
    // With a tab, the coin and its gold text ride a see-through pill
    // (#9559), built to sit on a photo: the scrim, not the photo, is what
    // the gold reads against ([scrimOf]).
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(2.0, 2.0, 7.0, 2.0),
          decoration: BoxDecoration(
            color: scrimOf(theme),
            borderRadius: BorderRadius.circular(999.0),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 4.0,
            children: [
              coin,
              Text(
                tab,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  color: theme.pangea.gold,
                  fontSize: (size * 0.75).clamp(10.0, 12.0),
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompletedStampPainter extends CustomPainter {
  final Color ink;
  final Color paper;

  _CompletedStampPainter({required this.ink, required this.paper});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(c, r, Paint()..color = paper);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..color = ink;
    canvas.drawCircle(c, r * 0.86, stroke..strokeWidth = r * 0.17);
    canvas.drawCircle(c, r * 0.6, stroke..strokeWidth = r * 0.1);
    final check = Path()
      ..moveTo(c.dx - r * 0.3, c.dy + r * 0.02)
      ..lineTo(c.dx - r * 0.08, c.dy + r * 0.24)
      ..lineTo(c.dx + r * 0.32, c.dy - r * 0.2);
    canvas.drawPath(
      check,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = ink
        ..strokeWidth = r * 0.17
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _CompletedStampPainter old) =>
      old.ink != ink || old.paper != paper;
}
