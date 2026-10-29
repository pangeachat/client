import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/notifications/notifications_constants.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/focus_ring_tap_target.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';

/// Shown on web in place of the notification permission prompt, since only
/// the app gets push. A computer gets a QR code its owner's phone can scan, in
/// the illustration's place; a phone browser gets its own store's badge
/// (get-the-app.instructions.md).
class SuggestMobileDialog extends StatelessWidget {
  const SuggestMobileDialog({super.key});

  static const double _qrCodeSize = 160.0;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final phoneStore = switch (defaultTargetPlatform) {
      TargetPlatform.iOS => _AppStore.apple,
      TargetPlatform.android => _AppStore.google,
      _ => null,
    };
    final getTheAppUri = Uri.parse(AppConfig.getTheAppURL);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 24.0,
              ),
              child: Column(
                spacing: 12.0,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (phoneStore != null)
                    ExcludeSemantics(
                      child: CachedNetworkImage(
                        imageUrl:
                            "${AppConfig.assetsBaseURL}/${NotificationsConstants.notifRequestImage}",
                        errorWidget: (_, _, _) => SizedBox.shrink(),
                      ),
                    ),
                  Semantics(
                    container: true,
                    child: Text(
                      l10n.enableNotificationsTitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Semantics(
                    container: true,
                    child: Text(
                      l10n.suggestMobileDesc,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                  if (phoneStore == null) ...[
                    // The link written out below says where this goes.
                    ExcludeSemantics(
                      child: SizedBox.square(
                        dimension: _qrCodeSize,
                        child: PrettyQrView.data(
                          data: AppConfig.getTheAppURL,
                          // Not theme roles: a QR code stays dark on light in
                          // both themes, because phone cameras read an
                          // inverted code unreliably.
                          decoration: const PrettyQrDecoration(
                            shape: PrettyQrSquaresSymbol(),
                            quietZone: PrettyQrQuietZone.standart,
                            background: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    // Typed into a phone by anyone who can't scan.
                    Semantics(
                      container: true,
                      child: Text(
                        '${getTheAppUri.host}${getTheAppUri.path}',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                  ],
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: _StoreBadge.clearSpace,
                    runSpacing: _StoreBadge.clearSpace,
                    children: [
                      for (final store
                          in phoneStore == null
                              ? _AppStore.values
                              : [phoneStore])
                        _StoreBadge(store),
                    ],
                  ),
                  Semantics(
                    container: true,
                    child: Text(
                      l10n.suggestMobileSignInSameAccount,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Semantics(
                    container: true,
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: theme.colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                        onPressed: () => Navigator.of(
                          context,
                        ).pop<OkCancelResult>(OkCancelResult.cancel),
                        child: Text(
                          l10n.gotIt,
                          // bodyLarge carries onSurface; the label needs the
                          // fill's ink.
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onPrimary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Close button
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                tooltip: L10n.of(context).close,
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(
                  context,
                ).pop<OkCancelResult>(OkCancelResult.cancel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The stores the app is in, in badge order: Apple asks for its badge to lead
/// a lineup.
enum _AppStore {
  apple(
    'Download on the App Store',
    'assets/pangea/app_store_badge.svg',
    119.66407 / 40,
  ),
  google(
    'Get it on Google Play',
    'assets/pangea/google_play_badge.png',
    564 / 168,
  );

  /// The words on the badge artwork, which is English in every locale.
  final String badgeLabel;
  final String badgeAsset;

  /// The artwork's width over its height, so the badge holds its place
  /// before the asset loads.
  final double badgeAspectRatio;

  const _AppStore(this.badgeLabel, this.badgeAsset, this.badgeAspectRatio);

  String get url => switch (this) {
    _AppStore.apple => AppConfig.iosAppStoreURL,
    _AppStore.google => AppConfig.androidUpdateURL,
  };
}

/// A store's official badge, unaltered, linking to the app's listing there.
class _StoreBadge extends StatelessWidget {
  final _AppStore store;

  const _StoreBadge(this.store);

  /// Apple's on-screen minimum; Google asks for the same size or larger.
  static const double height = 40.0;

  /// Both stores ask for a quarter of the badge's height around it.
  static const double clearSpace = height / 4;

  @override
  Widget build(BuildContext context) {
    final url = Uri.parse(store.url);
    // Named by the artwork's own words (accessibility.instructions.md: visible
    // label = accessible name). Not marked as English: that splits the tap
    // and focus onto a second node, and the web engine reads a link's name in
    // the UI voice whatever its language.
    return Semantics(
      container: true,
      link: true,
      linkUrl: url,
      label: store.badgeLabel,
      child: FocusRingTapTarget(
        onTap: () => launchUrl(url),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8.0)),
        ),
        ringStrokeAlign: BorderSide.strokeAlignOutside,
        child: switch (store) {
          _AppStore.apple => SvgPicture.asset(
            store.badgeAsset,
            height: height,
            width: height * store.badgeAspectRatio,
            excludeFromSemantics: true,
          ),
          _AppStore.google => Image.asset(
            store.badgeAsset,
            height: height,
            width: height * store.badgeAspectRatio,
            excludeFromSemantics: true,
          ),
        },
      ),
    );
  }
}
