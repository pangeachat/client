import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/activity_planner/activity_planner_page.dart';
import 'package:fluffychat/pangea/activity_suggestions/activity_suggestions_constants.dart';
import 'package:fluffychat/pangea/common/widgets/customized_svg.dart';

class ActivityPlannerPageAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  final PageMode pageMode;
  final String roomID;

  const ActivityPlannerPageAppBar({
    required this.pageMode,
    required this.roomID,
    super.key,
  });

  @override
  Size get preferredSize => const Size.fromHeight(72);

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);

    return AppBar(
      leadingWidth: FluffyThemes.isColumnMode(context) ? 150.0 : null,
      leading: FluffyThemes.isColumnMode(context)
          ? Row(
              children: [
                const SizedBox(width: 8.0),
                BackButton(
                  onPressed: Navigator.of(context).pop,
                ),
              ],
            )
          : null,
      title: pageMode == PageMode.savedActivities
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.save),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(l10n.mySavedActivities),
                ),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.event_note_outlined),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    l10n.activityPlannerTitle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
      actions: [
        FluffyThemes.isColumnMode(context)
            ? Container(
                width: 150.0,
                alignment: Alignment.center,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () =>
                      context.go('/rooms/$roomID/details/planner/generator'),
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(36.0),
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: 6.0,
                      horizontal: 10.0,
                    ),
                    child: Row(
                      spacing: 8.0,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CustomizedSvg(
                          svgUrl:
                              "${AppConfig.assetsBaseURL}/${ActivitySuggestionsConstants.crayonIconPath}",
                          colorReplacements: {
                            "#CDBEF9": colorToHex(
                              theme.colorScheme.secondary,
                            ),
                          },
                          height: 16.0,
                          width: 16.0,
                        ),
                        Flexible(
                          child: Text(
                            L10n.of(context).createActivity,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : IconButton(
                icon: const Icon(Icons.add),
                onPressed: () =>
                    context.go('/rooms/$roomID/details/planner/generator'),
              ),
      ],
    );
  }
}
