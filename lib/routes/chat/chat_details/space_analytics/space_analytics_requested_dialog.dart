import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/analytics_access/grant_analytics_access_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/full_width_dialog.dart';
import 'package:fluffychat/routes/analytics/analytics_page_constants.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

class SpaceAnalyticsRequestedDialog extends StatelessWidget {
  final Room room;
  final List<User> requestingUsers;
  const SpaceAnalyticsRequestedDialog({
    super.key,
    required this.room,
    required this.requestingUsers,
  });

  /// Shows the review dialog and applies the decision: grant force-joins each
  /// requesting admin into the learner's analytics rooms, deny kicks their
  /// knocks. [requests] maps each requesting admin to the analytics rooms
  /// they knocked on (AnalyticsRequestsBuilder's shape).
  ///
  /// Granting goes through the server-side grant endpoint rather than a plain
  /// invite. An invite left the admin *invited*, and every analytics read 403s
  /// until they are joined — so a teacher who asked from the dashboard, and
  /// never opens the app to accept, stayed stuck on "pending" forever however
  /// promptly the learner allowed them (#8177).
  static Future<void> show(
    BuildContext context,
    Room room,
    Map<User, List<Room>> requests,
  ) async {
    final resp = await showDialog(
      context: context,
      builder: (context) => SpaceAnalyticsRequestedDialog(
        room: room,
        requestingUsers: requests.keys.toList(),
      ),
    );
    if (resp is! bool || !context.mounted) return;

    await showFutureLoadingDialog(
      context: context,
      future: () async {
        for (final entry in requests.entries) {
          final futures = entry.value.map(
            (analyticsRoom) => resp
                ? room.client.grantInstructorAnalyticsAccess(
                    room.id,
                    analyticsRoom.id,
                    instructorId: entry.key.id,
                  )
                : analyticsRoom.kick(entry.key.id),
          );
          await Future.wait(futures);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isColumnMode = FluffyThemes.isColumnMode(context);
    return FullWidthDialog(
      maxHeight: 800.0,
      maxWidth: 450.0,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      dialogContent: Stack(
        children: [
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                spacing: 12.0,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    L10n.of(context).accessRequestedTitle,
                    style: TextStyle(fontSize: isColumnMode ? 24.0 : 20.0),
                  ),
                  Text(
                    L10n.of(context).accessRequestedDesc(
                      requestingUsers
                          .map((u) => u.calcDisplayname())
                          .join(", "),
                      room.getLocalizedDisplayname(),
                    ),
                    style: TextStyle(fontSize: isColumnMode ? 16.0 : 14.0),
                  ),
                  CachedNetworkImage(
                    imageUrl:
                        "${AppConfig.assetsBaseURL}/${AnalyticsPageConstants.dinoBotFileName}",
                    errorWidget: (context, e, s) => const SizedBox.shrink(),
                    progressIndicatorBuilder: (context, _, _) =>
                        const SizedBox.shrink(),
                    width: 150.0,
                  ),
                  const SizedBox(height: 50.0),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
              ),
              padding: const EdgeInsets.all(16.0),
              child: Row(
                spacing: 12.0,
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Row(
                        spacing: 12.0,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Symbols.approval_delegation),
                          Text(L10n.of(context).allow),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Row(
                        spacing: 12.0,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.visibility_off),
                          Text(L10n.of(context).deny),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 4.0,
            left: 4.0,
            child: IconButton.filled(
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHigh.withAlpha(170),
              ),
              icon: Icon(
                Icons.close_outlined,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              onPressed: Navigator.of(context).pop,
              tooltip: L10n.of(context).close,
            ),
          ),
        ],
      ),
    );
  }
}
