import 'dart:async';

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/features/join_codes/join_rule_extension.dart';
import 'package:fluffychat/features/user/direct_chat_contacts_extension.dart';
import 'package:fluffychat/features/user/user_directory_search.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/chat_details/invite/pangea_invitation_selection_view.dart';
import 'package:fluffychat/widgets/announcing_snackbar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

enum InvitationFilter {
  participants,
  space,
  contacts,
  knocking,
  invited,
  public,
  banned;

  static InvitationFilter? fromString(String value) =>
      InvitationFilter.values.firstWhereOrNull((e) => e.name == value);

  /// The most relevant starting filter for [room]'s invite flow: knocking
  /// users first, then the parent space's members, then contacts.
  static InvitationFilter defaultForRoom(Room room) {
    if (room.getParticipants([Membership.knock]).isNotEmpty) {
      return InvitationFilter.knocking;
    }
    return room.pangeaSpaceParents.isNotEmpty
        ? InvitationFilter.space
        : InvitationFilter.contacts;
  }

  static InvitationFilter? fromNullableString(String? value) =>
      value == null ? null : fromString(value);
}

/// Which filters the invite page can offer for a given room. Kept on [Room] so
/// the rules are decidable from room state alone, without a [BuildContext].
extension InvitationFiltersRoomExtension on Room {
  /// The course whose roster the "in this course" filter offers, or null when
  /// there is none to offer.
  ///
  /// For an activity session this is [Room.sourceCourse] — the course the session
  /// was LAUNCHED from, not merely a space parent — so a world-launched session
  /// gets no course filter (#8097).
  ///
  /// Every other room keeps the plain first-space-parent rule: a chat inside a
  /// course space really is "in this course".
  Room? get invitationCourseSpace {
    if (isActivitySession) return sourceCourse;
    final parents = pangeaSpaceParents;
    return parents.isEmpty ? null : parents.first;
  }

  /// Whether the invite page offers a roster ("participants") filter.
  ///
  /// An activity session's start page already lists everyone — role holders in
  /// their roles, the rest below them — so a second roster on the invite page is
  /// redundant there (#8097). Other rooms keep it; it is where the "N
  /// participants" button on the chat details page lands.
  bool get showInvitationParticipantsFilter => !isActivitySession;
}

class PangeaInvitationSelection extends StatefulWidget {
  final String roomId;
  final InvitationFilter? initialFilter;

  /// world_v2: the leading affordance supplied by the host panel (`←` back to
  /// the card / chat). Required: the room-gone error state renders its own
  /// chrome and must carry it (#8322, #8327). See `routing.instructions.md`.
  final Widget embeddedCloseButton;

  const PangeaInvitationSelection({
    super.key,
    required this.roomId,
    this.initialFilter,
    required this.embeddedCloseButton,
  });

  @override
  PangeaInvitationSelectionController createState() =>
      PangeaInvitationSelectionController();
}

class PangeaInvitationSelectionController
    extends State<PangeaInvitationSelection> {
  TextEditingController controller = TextEditingController();
  ScrollController scrollController = ScrollController();

  late final UserDirectorySearch directorySearch;

  bool get loading => directorySearch.loading;
  String? get lastSearch => directorySearch.lastSearch;

  /// The last directory-search failure, surfaced in place of the empty-results
  /// hint when there is nothing else to show.
  Object? get searchError =>
      directorySearch.results.isEmpty ? directorySearch.error : null;

  InvitationFilter filter = InvitationFilter.knocking;

  @override
  void initState() {
    super.initState();

    directorySearch = UserDirectorySearch(
      client: Matrix.of(context).client,
      onChanged: () {
        if (mounted) setState(() {});
      },
    );

    _room
        ?.requestParticipants(
          [
            Membership.join,
            Membership.invite,
            Membership.knock,
            Membership.ban,
          ],
          false,
          true,
        )
        .then((_) {
          if (mounted) setState(() {});
        });

    if (widget.initialFilter != null &&
        availableFilters.contains(widget.initialFilter)) {
      filter = widget.initialFilter!;
    } else if (spaceParent != null) {
      filter = InvitationFilter.space;
    } else if (_room?.getParticipants([Membership.knock]).isEmpty ?? true) {
      filter = InvitationFilter.contacts;
    }

    if (filter == InvitationFilter.public) {
      directorySearch.searchNow(controller.text);
    }

    controller.addListener(() {
      setState(() {});
    });

    _addJoinCode();
  }

  @override
  void dispose() {
    directorySearch.dispose();
    scrollController.dispose();
    super.dispose();
  }

  bool get showAcceptAll {
    if (filter != InvitationFilter.knocking) {
      return false;
    }

    return filteredContacts().isNotEmpty;
  }

  String filterLabel(InvitationFilter filter) {
    final l10n = L10n.of(context);
    switch (filter) {
      case InvitationFilter.space:
        return l10n.inThisSpace;
      case InvitationFilter.contacts:
        return l10n.myContacts;
      case InvitationFilter.invited:
        return l10n.numInvited(_room?.summary.mInvitedMemberCount ?? 0);
      case InvitationFilter.knocking:
        return l10n.numKnocking(
          participants?.where((u) => u.membership == Membership.knock).length ??
              0,
        );
      case InvitationFilter.public:
        return l10n.public;
      case InvitationFilter.participants:
        return l10n.participants;
      case InvitationFilter.banned:
        return l10n.banned;
    }
  }

  Room? get _room => Matrix.of(context).client.getRoomById(widget.roomId);

  Room? get spaceParent => _room?.invitationCourseSpace;

  bool get showInviteAllInSpaceButton {
    final roomParticipants = participants;
    if (roomParticipants == null ||
        filter != InvitationFilter.space ||
        spaceParent == null) {
      return false;
    }

    final spaceParticipants = spaceParent!.getParticipants();
    return spaceParticipants.any(
      (participant) => !roomParticipants.any((p) => p.id == participant.id),
    );
  }

  List<InvitationFilter> get availableFilters => InvitationFilter.values
      .where(
        (f) => switch (f) {
          InvitationFilter.space => spaceParent != null,
          InvitationFilter.contacts => true,
          InvitationFilter.invited =>
            participants?.any((u) => u.membership == Membership.invite) ??
                false,
          InvitationFilter.knocking =>
            participants?.any((u) => u.membership == Membership.knock) ?? false,
          InvitationFilter.banned =>
            participants?.any((u) => u.membership == Membership.ban) ?? false,
          InvitationFilter.public => true,
          InvitationFilter.participants =>
            _room?.showInvitationParticipantsFilter ?? true,
        },
      )
      .toList();

  List<User>? get participants {
    return _room?.getParticipants([
      Membership.join,
      Membership.invite,
      Membership.knock,
      Membership.ban,
    ]);
  }

  List<Membership> get _membershipOrder => [
    Membership.join,
    Membership.invite,
    Membership.knock,
    Membership.leave,
    Membership.ban,
  ];

  String? membershipCopy(Membership? membership) => switch (membership) {
    Membership.ban => L10n.of(context).banned,
    Membership.invite => L10n.of(context).invited,
    Membership.join => null,
    Membership.knock => L10n.of(context).knocking,
    Membership.leave => L10n.of(context).leftTheChat,
    null => null,
  };

  int _sortUsers(User a, User b) {
    // sort yourself to the top
    final client = Matrix.of(context).client;
    if (a.id == client.userID) return -1;
    if (b.id == client.userID) return 1;

    // sort the bot to the top
    if (a.id == BotName.byEnvironment) return -1;
    if (b.id == BotName.byEnvironment) return 1;

    if (participants != null) {
      final participantA = participants!.firstWhereOrNull((u) => u.id == a.id);
      final participantB = participants!.firstWhereOrNull((u) => u.id == b.id);
      // sort all participants first, with admins first, then moderators, then the rest
      if (participantA?.membership == null &&
          participantB?.membership != null) {
        return 1;
      }
      if (participantA?.membership != null &&
          participantB?.membership == null) {
        return -1;
      }
      if (participantA?.membership != null &&
          participantB?.membership != null) {
        final aIndex = _membershipOrder.indexOf(participantA!.membership);
        final bIndex = _membershipOrder.indexOf(participantB!.membership);
        if (aIndex != bIndex) {
          return aIndex.compareTo(bIndex);
        }
      }
    }

    // finally, sort by displayname
    final aName = a.calcDisplayname().toLowerCase();
    final bName = b.calcDisplayname().toLowerCase();
    return aName.compareTo(bName);
  }

  void setFilter(InvitationFilter newFilter) {
    if (filter == newFilter) return;
    if (newFilter == InvitationFilter.public) {
      directorySearch.searchNow(controller.text);
    }
    if (scrollController.hasClients) {
      scrollController.jumpTo(0);
    }
    setState(() => filter = newFilter);
  }

  List<User> filteredContacts() {
    List<User> contacts = switch (filter) {
      InvitationFilter.space => spaceParent?.getParticipants() ?? [],
      InvitationFilter.contacts => getContacts(context),
      InvitationFilter.invited =>
        participants
                ?.where((u) => u.membership == Membership.invite)
                .toList() ??
            [],
      InvitationFilter.knocking =>
        participants?.where((u) => u.membership == Membership.knock).toList() ??
            [],
      InvitationFilter.banned =>
        participants?.where((u) => u.membership == Membership.ban).toList() ??
            [],
      InvitationFilter.participants || InvitationFilter.public =>
        participants?.where((u) => u.membership != Membership.ban).toList() ??
            [],
    };

    final search = controller.text.toLowerCase();
    contacts = contacts
        .where(
          (u) =>
              u.calcDisplayname().toLowerCase().contains(search) ||
              u.id.toLowerCase().contains(search),
        )
        .toList();

    final room = _room;
    if (room != null && (room.isSpace || room.showActivityChatUI)) {
      contacts.removeWhere((u) => u.id == BotName.byEnvironment);
    }

    contacts.sort(_sortUsers);
    return contacts;
  }

  List<User> getContacts(BuildContext context) {
    final contacts = Matrix.of(context).client.directChatContacts;

    // The bot is a candidate for a chat even before it shares a direct chat
    // with this user, but never for a space.
    if (_room?.isSpace == false &&
        !contacts.any((u) => u.id == BotName.byEnvironment)) {
      final bot = _room?.unsafeGetUserFromMemoryOrFallback(
        BotName.byEnvironment,
      );
      if (bot != null) contacts.add(bot);
    }

    return contacts;
  }

  void searchUserWithCoolDown(String text) {
    if (filter != InvitationFilter.public) return;
    directorySearch.search(text);
  }

  /// The directory results this room can actually act on: the bot is not a
  /// candidate for a space, a raw Matrix ID the directory does not return is
  /// still invitable by hand, and anyone already in the room is dropped.
  List<Profile> get foundProfiles {
    final text = controller.text;
    if (text.isValidMatrixId &&
        directorySearch.results.every((p) => p.userId != text)) {
      return [
        Profile.fromJson({ModelKey.userId: text}),
      ];
    }

    final profiles = [...directorySearch.results];
    if (_room?.isSpace ?? false) {
      profiles.removeWhere((p) => p.userId == BotName.byEnvironment);
    }

    final members = participants
        ?.where(
          (user) =>
              [Membership.join, Membership.invite].contains(user.membership),
        )
        .map((user) => user.id)
        .toSet();
    // `participants` is null until the room's member list has loaded. It used
    // to drop every result in that window (`null != -1` is true), which read
    // as "nobody by that name" on a room that simply had not finished loading.
    if (members != null) {
      profiles.removeWhere((p) => members.contains(p.userId));
    }
    return profiles;
  }

  Future<void> _addJoinCode() async {
    if (_room == null || _room!.joinCode != null) return;
    if (!_room!.canChangeStateEvent(EventTypes.RoomJoinRules)) return;

    try {
      await _room!.generateAndSetJoinCode();
      if (mounted) setState(() {});
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {'roomId': _room!.id});
    }
  }

  void inviteAction(String userID) async {
    final room = Matrix.of(context).client.getRoomById(widget.roomId)!;

    final success = await showFutureLoadingDialog(
      context: context,
      future: () async {
        await room.invite(userID);
        if (room.courseParent != null && room.courseParent!.canInvite) {
          await room.courseParent!.requestParticipants(
            [Membership.join, Membership.invite],
            false,
            true,
          );

          final existingParticipant = room.courseParent!
              .getParticipants()
              .firstWhereOrNull((u) => u.id == userID);

          if (existingParticipant == null ||
              ![
                Membership.invite,
                Membership.join,
              ].contains(existingParticipant.membership)) {
            await room.courseParent!.invite(userID);
          }
        }
      },
    );
    if (success.error == null) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBarAnnounced(
        SnackBar(
          content: Text(
            room.isSpace
                ? L10n.of(context).contactHasBeenInvitedToTheCourse
                : L10n.of(context).contactHasBeenInvitedToTheChat,
          ),
          showCloseIcon: true,
        ),
      );
    }
  }

  Future<void> inviteAllInSpace() async {
    if (_room == null) return;
    final spaceParticipants = spaceParent?.getParticipants() ?? [];

    if (spaceParticipants.isEmpty) return;

    final List<Future> futures = [];
    for (final user in spaceParticipants) {
      if (participants?.any((u) => u.id == user.id) ?? false) {
        // User is already in the room
        continue;
      }

      if (user.id == Matrix.of(context).client.userID) continue;
      futures.add(_room!.invite(user.id));
    }

    await showFutureLoadingDialog(
      context: context,
      future: () async {
        await Future.wait(futures);
        return null; // No error
      },
    ).then((result) {
      if (result.error == null) {
        ScaffoldMessenger.of(context).showSnackBarAnnounced(
          SnackBar(
            content: Text(
              L10n.of(context).spaceParticipantsHaveBeenInvitedToTheChat,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBarAnnounced(
          SnackBar(content: Text(result.error.toString())),
          assertive: true,
        );
      }
    });
  }

  Future<void> acceptAllKnocking() async {
    if (_room == null) return;

    final knocking =
        participants?.where((u) => u.membership == Membership.knock).toList() ??
        [];
    if (knocking.isEmpty) return;

    final futures = knocking.map((u) async {
      _room!.invite(u.id);
      if (u.membership != Membership.invite) {
        await _room!.client.onSync.stream.firstWhere(
          (update) =>
              update.rooms?.join?[widget.roomId]?.timeline?.events?.any(
                (event) =>
                    event.type == EventTypes.RoomMember &&
                    event.stateKey == u.id &&
                    event.content['membership'] == 'invite',
              ) ==
              true,
        );
      }
    }).toList();

    await showFutureLoadingDialog(
      context: context,
      future: () => Future.wait(futures),
    );

    if (!mounted) return;

    final updatedContacts = filteredContacts();
    if (updatedContacts.isEmpty) {
      setFilter(InvitationFilter.invited);
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => PangeaInvitationSelectionView(this);
}
