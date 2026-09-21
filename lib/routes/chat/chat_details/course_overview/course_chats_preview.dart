import 'dart:async';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_section_button.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_section_header.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_section_shortcut.dart';
import 'package:fluffychat/routes/chat/chat_details/space_details_content.dart';
import 'package:fluffychat/routes/chat_list/chat_list_item.dart';
import 'package:fluffychat/routes/chat_list/course_default_chats_enum.dart';
import 'package:fluffychat/routes/chat_list/course_hierarchy_extension.dart';
import 'package:fluffychat/routes/chat_list/default_chat_creation_tile.dart';
import 'package:fluffychat/routes/chat_list/hierarchy_sync_update_extension.dart';
import 'package:fluffychat/utils/stream_extension.dart';

/// The course page's Chats section: its header and, below, the admin's
/// default-chat creation suggestions, then the most recently active joined
/// chats in the course — group chats and activity sessions alike — capped at
/// [maxChats]. Discovery (unjoined chats, invites, open sessions) stays on the
/// section's "All chats" subpage, [CourseChats].
///
/// This widget owns the whole section, trailing divider included, because
/// whether the section shows at all and whether its header offers "See all"
/// turn on the same counts (#9183):
///
/// - "See all" shows only when the subpage holds a chat this section does
///   not: more joined chats than fit, an invite or knock, or a group chat the
///   user can join. A subpage repeating the same rows, or an empty one, is not
///   worth offering. A coursemate's open activity session is not counted — the
///   Activities row and the map already offer it.
/// - The section shows only when it has something in it: a joined chat, a
///   "See all", or — for an admin — the create shortcut and suggestions, since
///   this is where an admin makes the course's chats.
class CourseChatsPreview extends StatefulWidget {
  final Room room;

  /// Opens the section's "All chats" subpage.
  final VoidCallback onShowAll;

  /// Creates a course group chat — the header's shortcut.
  final VoidCallback onCreateChat;

  static const int maxChats = 2;

  /// The most often a burst of course updates (a class launching sessions,
  /// each one a new course child) reloads the hierarchy.
  static const Duration hierarchyReloadInterval = Duration(seconds: 5);

  const CourseChatsPreview({
    required this.room,
    required this.onShowAll,
    required this.onCreateChat,
    super.key,
  });

  @override
  State<CourseChatsPreview> createState() => _CourseChatsPreviewState();
}

class _CourseChatsPreviewState extends State<CourseChatsPreview> {
  /// Whether the course has a group chat this user can join but has not;
  /// null until the course hierarchy answers.
  bool? _hasJoinableGroupChat;

  /// Tags each hierarchy load, so an answer that a newer load (or a switch
  /// to another course) has overtaken is dropped.
  int _hierarchyLoad = 0;

  StreamSubscription? _hierarchySubscription;

  Room get _course => widget.room;

  @override
  void initState() {
    super.initState();
    _watchHierarchy();
  }

  @override
  void didUpdateWidget(covariant CourseChatsPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room.id != widget.room.id) {
      _hasJoinableGroupChat = null;
      _watchHierarchy();
    }
  }

  @override
  void dispose() {
    _hierarchySubscription?.cancel();
    super.dispose();
  }

  Set<String> get _childIds =>
      _course.spaceChildren.map((c) => c.roomId).whereType<String>().toSet();

  /// Loads now, then again whenever a chat is added to the course or the user
  /// joins, leaves or is invited to one — the same updates the subpage
  /// reloads on, rate-limited to [CourseChatsPreview.hierarchyReloadInterval].
  void _watchHierarchy() {
    _hierarchySubscription?.cancel();
    _hierarchySubscription = _course.client.onSync.stream
        .where(
          (update) => update.hasHierarchyUpdate(
            roomId: _course.id,
            userID: _course.client.userID,
            childrenIds: _childIds,
          ),
        )
        .rateLimit(CourseChatsPreview.hierarchyReloadInterval)
        .listen((_) => _loadJoinableGroupChat());
    _loadJoinableGroupChat();
  }

  Future<void> _loadJoinableGroupChat() async {
    final load = ++_hierarchyLoad;
    // The rooms the client already has offer "See all" on their own, so the
    // hierarchy can't change the answer. Every change that could take that
    // away (leaving a chat, answering an invite) is a hierarchy update, which
    // loads again.
    if (_offersMoreLocally(_courseChats)) return;

    bool hasJoinable;
    try {
      hasJoinable = await _course.hasJoinableGroupChat();
    } catch (e, s) {
      ErrorHandler.logErrorOnce(
        key: 'course-chats-hierarchy:${_course.id}',
        e: e,
        s: s,
        data: {'courseId': _course.id},
      );
      // Offer the subpage, which shows its own load error, rather than hide
      // a chat the user may be able to join.
      hasJoinable = true;
    }
    if (!mounted || load != _hierarchyLoad) return;
    setState(() => _hasJoinableGroupChat = hasJoinable);
  }

  /// Visible, non-space children of the course in `client.rooms` — joined,
  /// invited or knocking — in the client's recency order (client.rooms is
  /// sorted by latest activity). Hidden rooms (analytics, archived
  /// activities) are filtered exactly as the full chat list filters them.
  List<Room> get _courseChats {
    final childIds = _childIds;
    return _course.client.rooms
        .where((r) => childIds.contains(r.id) && !r.isSpace && !r.isHiddenRoom)
        .toList();
  }

  static List<Room> _joined(List<Room> chats) =>
      chats.where((r) => r.membership == Membership.join).toList();

  /// Whether [chats] alone give the subpage more than the section shows: more
  /// joined chats than fit, or an invite or knock.
  static bool _offersMoreLocally(List<Room> chats) {
    final joined = _joined(chats);
    return joined.length > CourseChatsPreview.maxChats ||
        joined.length < chats.length;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: _course.client.onSync.stream
          .where((s) => s.hasRoomUpdate)
          .rateLimit(const Duration(seconds: 1)),
      builder: (context, _) {
        final chats = _courseChats;
        final joined = _joined(chats);
        final showAll =
            _offersMoreLocally(chats) || (_hasJoinableGroupChat ?? false);
        if (joined.isEmpty && !showAll && !_course.isRoomAdmin) {
          return const SizedBox.shrink();
        }

        final l10n = L10n.of(context);
        final title = SpaceSettingsTabs.chat.title(context);
        final titleFontSize = Theme.of(context).textTheme.bodyMedium?.fontSize;
        final subtitleFontSize = Theme.of(
          context,
        ).textTheme.bodySmall?.fontSize;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: SpaceDetailsContent.sectionPadding,
              child: CourseSectionHeader(
                title: title,
                icon: Icons.forum_outlined,
                actions: [
                  // Creating a course chat is buried in the More section's
                  // settings list; teachers asked for it where the chats are
                  // (#8744). Same permission gate as that row — the shortcut
                  // can't do what the setting wouldn't.
                  if (_course.isRoomAdmin &&
                      _course.canChangeStateEvent(EventTypes.SpaceChild))
                    CourseSectionShortcut(
                      icon: Symbols.chat_add_on,
                      tooltip: l10n.createGroupChat,
                      onPressed: widget.onCreateChat,
                    ),
                  if (showAll)
                    CourseSectionButton(
                      section: title,
                      onPressed: widget.onShowAll,
                    ),
                ],
              ),
            ),
            // The chat rows carry their own 8px wrapper (ChatListItem /
            // DefaultChatCreationTile), so the section pads them by the
            // difference — their content then sits at the same inset as
            // every other section.
            Padding(
              padding:
                  SpaceDetailsContent.sectionPadding -
                  const EdgeInsets.symmetric(horizontal: 8.0),
              child: Column(
                children: [
                  // The admin's create-introductions/announcements suggestions
                  // ride the preview too — an admin who never opens "All
                  // chats" must still see them. Both self-hide once created
                  // or dismissed.
                  for (final type in CourseDefaultChatsEnum.values)
                    DefaultChatCreationTile(
                      space: _course,
                      type: type,
                      titleFontSize: titleFontSize,
                      subtitleFontSize: subtitleFontSize,
                    ),
                  for (final chat in joined.take(CourseChatsPreview.maxChats))
                    ChatListItem(
                      chat,
                      titleFontSize: titleFontSize,
                      subtitleFontSize: subtitleFontSize,
                      onTap: () => context.go(
                        WorkspaceNav.openRoomById(
                          GoRouterState.of(context).uri,
                          chat.id,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(),
          ],
        );
      },
    );
  }
}
