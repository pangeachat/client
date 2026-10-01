import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';

/// The header row shared by both workspace panel columns: a [leading]
/// close/back control at the start, a small gap, then the panel [title].
///
/// The two columns ([WorkspaceLeftPanel] / [WorkspaceRightPanel]) keep their own
/// close LOGIC — they rewrite different `?left=`/`?right=` lists and decide `←`
/// vs `X` separately — but the header CHROME (padding, control-to-title gap, and
/// the title's single-line ellipsised titleMedium/w600 styling) is identical, so
/// it lives here once and can't drift between columns. The surrounding
/// floating-card surface is [PanelCard]. See `routing.instructions.md`.
class PanelHeader extends StatelessWidget {
  /// The leading control — an `IconButton`/`BackButton` the column built from its
  /// own close affordance. Placed at the row's start. Null for a header whose
  /// only control rides [trailing] — the wide course card, whose chevron sits
  /// beside its share / focus actions (#8866); the title then starts at
  /// [contentInset], level with those trailing glyphs.
  final Widget? leading;

  /// The panel title shown beside [leading]; empty for panels whose body renders
  /// its own title.
  final String title;

  /// Rendered in the title slot instead of [title] when set — for titles a
  /// single string can't express (the course subpage's breadcrumb). It
  /// inherits the header's canonical text style, so composed titles can't
  /// drift from plain ones.
  final Widget? titleWidget;

  final Widget? trailing;

  const PanelHeader({
    super.key,
    required this.leading,
    required this.title,
    this.titleWidget,
    this.trailing,
  });

  static const double horizontalPadding = 8.0;

  /// The header's vertical padding on wide; narrow headers carry none.
  static const double wideVerticalPadding = 16.0;

  /// The glyph size of a default [Icon] — Flutter's own `IconThemeData` default.
  static const double _iconSize = 24.0;

  /// How far a trailing `IconButton`'s glyph sits in from the header's edge:
  /// the padding plus the icon's inset inside its 48px target. A header with
  /// no [leading] starts its title here too, so text and glyphs share one
  /// edge — and the course's collapsed progress bar insets to it, ending
  /// where the buttons end instead of running past them (#8866).
  static const double contentInset =
      horizontalPadding + (kMinInteractiveDimension - _iconSize) / 2;

  /// The header's height on wide — its control targets plus the padding — so
  /// the course context bar, which is this header with the panel shut, can
  /// state its own height ([CourseContextBar.height]).
  static const double wideHeight =
      kMinInteractiveDimension + 2 * wideVerticalPadding;

  /// The canonical panel-title style. Published so chrome that IS a panel
  /// header with the panel closed — the course context bar — cannot drift
  /// from the real header the way it had (titleMedium/w600 against this
  /// header's wide titleLarge, #8816).
  static TextStyle? titleStyle(BuildContext context) =>
      FluffyThemes.isColumnMode(context)
      ? Theme.of(context).textTheme.titleLarge
      : Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600);

  @override
  Widget build(BuildContext context) {
    final leading = this.leading;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: FluffyThemes.isColumnMode(context)
            ? wideVerticalPadding
            : 0.0,
      ),
      child: Row(
        children: [
          if (leading != null) ...[
            leading,
            const SizedBox(width: 8),
          ] else
            const SizedBox(width: contentInset - horizontalPadding),
          Expanded(
            child: ExcludeSemantics(
              child: DefaultTextStyle.merge(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: titleStyle(context),
                child: titleWidget ?? Text(title),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
