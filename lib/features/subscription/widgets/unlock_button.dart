import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/subscription/widgets/decorative_stars.dart';
import 'package:fluffychat/pangea/common/widgets/pressable_button.dart';

/// The gold call to action every subscription gate ends on: it opens the
/// subscription settings page.
///
/// Gold, not the theme's primary — the gates advertise a paid feature, and
/// sharing the primary made them read as ordinary controls rather than an
/// upsell (#7929). [label] names the feature being unlocked rather than the
/// purchase, so the gate pitches the value and not the transaction.
class UnlockButton extends StatelessWidget {
  final String label;
  final double fontSize;
  final EdgeInsetsGeometry padding;

  /// Whether the two stars that hug the pill are drawn. They sit BEHIND it, so
  /// the label keeps its full contrast against the gold. The larger, scattered
  /// stars a card carries come from [DecorativeStars] instead.
  final bool showStars;

  const UnlockButton({
    super.key,
    required this.label,
    this.fontSize = 20.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
    this.showStars = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!showStars) {
      return _UnlockPill(label: label, fontSize: fontSize, padding: padding);
    }

    // Deliberately NOT a mirrored pair: matched stars at opposite corners read
    // as a laid-out frame rather than scatter (#7929 review). Different sizes,
    // and the upper star sits along the pill's top edge instead of its corner.
    //
    // The pill is LAST so it paints over the stars and keeps its contrast.
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        const Positioned(
          bottom: -12.0,
          left: -16.0,
          child: DecorativeStar(size: 34.0, rotation: -0.28),
        ),
        const Positioned(
          top: -14.0,
          right: 22.0,
          child: DecorativeStar(size: 22.0, rotation: 0.55),
        ),
        _UnlockPill(label: label, fontSize: fontSize, padding: padding),
      ],
    );
  }
}

/// The pill itself, split out so [UnlockButton] can place it with or without
/// stars without holding a widget in a variable.
class _UnlockPill extends StatelessWidget {
  static const BorderRadius _borderRadius = BorderRadius.all(
    Radius.circular(36),
  );

  final String label;
  final double fontSize;
  final EdgeInsetsGeometry padding;

  const _UnlockPill({
    required this.label,
    required this.fontSize,
    required this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final gold = AppConfig.goldByTheme(context);

    return PressableButton(
      borderRadius: _borderRadius,
      color: gold,
      // The current URI comes from the router, NOT from `GoRouterState.of`:
      // several of these gates render inside an `OverlayEntry` — the word card
      // over a vocab chip or a message, the chat toolbar's mode gates. An entry
      // sits BESIDE the route's page in the Navigator's overlay rather than
      // under it, so `GoRouterState.of` finds no `ModalRoute` and throws. The
      // throw landed in an async tap handler, so the button did nothing at all
      // (#8622).
      onPressed: () => context.go(
        WorkspaceNav.openSettings(
          GoRouter.of(context).routeInformationProvider.value.uri,
          page: 'subscription',
        ),
      ),
      builder: (context, depressed, shadowColor) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: depressed ? shadowColor : gold,
          borderRadius: _borderRadius,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: AppConfig.onGoldByTheme(context),
          ),
        ),
      ),
    );
  }
}
