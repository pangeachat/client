import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';

/// A course-page section's "See all" button, opening the section's full
/// subpage within the card.
///
/// It rides its section header's action row (#8744), where it sits beside
/// the title rather than below the section's content: a priority action, in
/// the same place for every section, reachable without scrolling the section
/// first. The header places it, so the button carries no padding or alignment
/// of its own.
///
/// A tonal pill rather than a text link (#8815): as primary-colored text it
/// was the quietest thing in its row and easy to miss, while a solid fill
/// would put four calls to action on one page at the level of "Join" (#8475
/// tried that, under the sections). Tonal is the app's middle emphasis — the
/// pill the course-code page and the add-course options already use.
///
/// Every section's link reads the same "See all" — the section it belongs to
/// is already named by the header beside it, so repeating it in the label
/// only adds words. A screen reader gets no such adjacency, which is why
/// [section] names it in the accessible name instead: four buttons that all
/// spoke "See all" would be untellable apart.
class CourseSectionButton extends StatelessWidget {
  /// The section's display title, for the accessible name only.
  final String section;
  final VoidCallback onPressed;

  const CourseSectionButton({
    required this.section,
    required this.onPressed,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    // The label alone, with no trailing chevron (#8898): a chevron glyph is
    // drawn inside a 24px box with about 5px of its own space either side of
    // it, so it cannot sit evenly against a button's padding — every Material
    // button pads its two ends alike (24/24) or pads the icon's end wider
    // (16/24, and it doesn't flip for a trailing icon), and both render the
    // pill's right side wider than its left. Dropping it is what makes the
    // two sides match at every text scale, and it shortens the pill, which
    // is what the report asked for. The tonal fill is the affordance.
    //
    // A long localization can outrun a narrow course column; the label is a
    // plain [Text], so it wraps inside the width the header allows it rather
    // than overflowing the header's row.
    return FilledButton.tonal(
      onPressed: onPressed,
      child: Text(l10n.seeAll, semanticsLabel: l10n.seeAllSection(section)),
    );
  }
}
