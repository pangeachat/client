import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/join_codes/join_rule_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/firebase_analytics.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat_list/course_default_chats_enum.dart';
import 'package:fluffychat/routes/chat_list/default_chats_room_extension.dart';
import 'package:fluffychat/utils/navigation_util.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

/// Admin-only suggestion row to create one of a course's default chats
/// (introductions / announcements), with a dismiss control. Hides itself for
/// non-admins and once the chat exists or the suggestion was dismissed.
/// Shared by the full course chat list and the course page's Chats section
/// preview, so admins can't miss it (#8357).
class DefaultChatCreationTile extends StatelessWidget {
  final Room space;
  final CourseDefaultChatsEnum type;

  /// The course's discovered-but-unjoined hierarchy children, when the
  /// caller has them loaded: an existing unjoined default chat then also
  /// hides the tile. Callers without the hierarchy (the course page's Chats
  /// preview) pass null and skip that check.
  final List<SpaceRoomsChunk$2>? discoveredChildren;

  /// Optional text-size overrides so an embedding page can match its own
  /// type ladder; null keeps the list defaults.
  final double? titleFontSize;
  final double? subtitleFontSize;

  const DefaultChatCreationTile({
    required this.space,
    required this.type,
    this.discoveredChildren,
    this.titleFontSize,
    this.subtitleFontSize,
    super.key,
  });

  bool get _visible {
    if (!space.isRoomAdmin) return false;
    if (space.dismissedDefaultChat(type) || space.hasDefaultChat(type)) {
      return false;
    }
    // The chat can exist without being joined yet, in which case it's not in
    // client.rooms (which hasDefaultChat checks) but in the discovered
    // hierarchy children.
    return !(discoveredChildren ?? []).any(
      (chunk) => (chunk.canonicalAlias?.localpart ?? '').startsWith(type.alias),
    );
  }

  Future<void> _create(BuildContext context) async {
    final roomId = await space.addDefaultChat(
      type: type,
      name: type.title(L10n.of(context)),
    );

    GoogleAnalytics.createChat(roomId);
    final classCode = space.joinCode;
    if (classCode != null) {
      GoogleAnalytics.addParent(roomId, classCode);
    }

    if (!context.mounted) return;
    NavigationUtil.goToSpaceRoute(roomId, const [], context);
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox();

    final l10n = L10n.of(context);
    // The same rounded wrapper [ChatListItem] uses, so the tile's surface and
    // ink match the chat rows it sits between.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        clipBehavior: Clip.hardEdge,
        color: Colors.transparent,
        child: ListTile(
          leading: const Icon(Symbols.chat_add_on),
          title: Text(
            type.creationTitle(l10n),
            style: TextStyle(fontSize: titleFontSize),
          ),
          subtitle: Text(
            type.creationDesc(l10n),
            style: TextStyle(fontSize: subtitleFontSize),
          ),
          trailing: IconButton(
            tooltip: l10n.dismiss,
            icon: const Icon(Icons.close),
            onPressed: () => showFutureLoadingDialog(
              context: context,
              future: () => space.dismissDefaultChatCreation(type),
            ),
          ),
          onTap: () => showFutureLoadingDialog(
            context: context,
            future: () => _create(context),
          ),
        ),
      ),
    );
  }
}
