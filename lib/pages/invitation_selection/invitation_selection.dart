import 'dart:async';

import 'package:adaptive_dialog/adaptive_dialog.dart';
import 'package:collection/collection.dart';
import 'package:fluffychat/pages/invitation_selection/invitation_selection_view.dart';
import 'package:fluffychat/pangea/constants/class_default_values.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension/pangea_room_extension.dart';
import 'package:fluffychat/pangea/utils/bot_name.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:future_loading_dialog/future_loading_dialog.dart';
import 'package:matrix/matrix.dart';

import '../../utils/localized_exception_extension.dart';

//#Pangea
enum InvitationSelectionMode { admin, member }
//Pangea#

class InvitationSelection extends StatefulWidget {
  final String roomId;
  const InvitationSelection({
    super.key,
    required this.roomId,
  });

  @override
  InvitationSelectionController createState() =>
      InvitationSelectionController();
}

class InvitationSelectionController extends State<InvitationSelection> {
  TextEditingController controller = TextEditingController();
  late String currentSearchTerm;
  bool loading = false;
  List<Profile> foundProfiles = [];
  Timer? coolDown;

  String? get roomId => widget.roomId;

  Future<List<User>> getContacts(BuildContext context) async {
    final client = Matrix.of(context).client;
    final room = client.getRoomById(roomId!)!;
    final participants = await room.requestParticipants();
    participants.removeWhere(
      (u) => ![Membership.join, Membership.invite].contains(u.membership),
    );
    final contacts = client.rooms
        .where((r) => r.isDirectChat)
        // #Pangea
        // .map((r) => r.unsafeGetUserFromMemoryOrFallback(r.directChatMatrixID!))
        .map(
          (r) => r
              .getParticipants()
              .firstWhereOrNull((u) => u.id != client.userID),
        )
        // Pangea#
        .toList();
    // #Pangea
    contacts.removeWhere((u) => u == null || u.id != BotName.byEnvironment);
    contacts.sort(
      (a, b) => a!.calcDisplayname().toLowerCase().compareTo(
            b!.calcDisplayname().toLowerCase(),
          ),
    );
    return contacts.cast<User>();
    // contacts.sort(
    //   (a, b) => a.calcDisplayname().toLowerCase().compareTo(
    //         b.calcDisplayname().toLowerCase(),
    //       ),
    // );
    // return contacts;
    //Pangea#
  }

  //#Pangea
  // add all students (already local) from spaceParents who aren't already in room to eligibleStudents
  // use room.members to get all users in room
  bool _initialized = false;
  Future<List<User>> eligibleStudents(
    BuildContext context,
    String text,
  ) async {
    if (!_initialized) {
      _initialized = true;
      await requestParentSpaceParticipants();
    }

    final eligibleStudents = <User>[];
    final spaceParents = room?.pangeaSpaceParents;
    if (spaceParents == null) return eligibleStudents;

    final userId = Matrix.of(context).client.userID;
    for (final Room space in spaceParents) {
      eligibleStudents.addAll(
        space.getParticipants().where(
              (spaceUser) =>
                  spaceUser.id != BotName.byEnvironment &&
                  spaceUser.id != "@support:staging.pangea.chat" &&
                  spaceUser.id != userId &&
                  (text.isEmpty ||
                      (spaceUser.displayName
                              ?.toLowerCase()
                              .contains(text.toLowerCase()) ??
                          false) ||
                      spaceUser.id.toLowerCase().contains(text.toLowerCase())),
            ),
      );
    }
    return eligibleStudents;
  }

  Future<SearchUserDirectoryResponse>
      eligibleStudentsAsSearchUserDirectoryResponse(
    BuildContext context,
    String text,
  ) async {
    return SearchUserDirectoryResponse(
      results: (await eligibleStudents(context, text))
          .map(
            (e) => Profile(
              userId: e.id,
              avatarUrl: e.avatarUrl,
              displayName: e.displayName,
            ),
          )
          .toList(),
      limited: false,
    );
  }

  List<User?> studentsInRoom(BuildContext context) =>
      room
          ?.getParticipants()
          .where(
            (u) => [Membership.join, Membership.invite].contains(u.membership),
          )
          .toList() ??
      <User>[];
  //Pangea#

  // #Pangea
  // void inviteAction(BuildContext context, String id, String displayname) async {
  void inviteAction(
    BuildContext context,
    String id,
    String displayname, {
    InvitationSelectionMode? mode,
  }) async {
    // Pangea#
    final room = Matrix.of(context).client.getRoomById(roomId!)!;
    if (OkCancelResult.ok !=
        await showOkCancelAlertDialog(
          context: context,
          title: L10n.of(context)!.inviteContact,
          message: L10n.of(context)!.inviteContactToGroupQuestion(
            displayname,
            room.getLocalizedDisplayname(
              MatrixLocals(L10n.of(context)!),
            ),
          ),
          okLabel: L10n.of(context)!.invite,
          cancelLabel: L10n.of(context)!.cancel,
        )) {
      return;
    }
    final success = await showFutureLoadingDialog(
      context: context,
      //#Pangea
      // future: () => room.invite(id),
      future: () async {
        if (mode == InvitationSelectionMode.admin) {
          await inviteTeacherAction(room, id);
        } else {
          await room.invite(id);
        }
      },
      // Pangea#
    );
    if (success.error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          // #Pangea
          // content: Text(L10n.of(context)!.contactHasBeenInvitedToTheGroup),
          content: Text(L10n.of(context)!.contactHasBeenInvitedToTheChat),
          // Pangea#
        ),
      );
    }
  }

  // #Pangea
  Future<void> inviteTeacherAction(Room room, String id) async {
    await room.invite(id);
    await room.setPower(id, ClassDefaultValues.powerLevelOfAdmin);
  }
  // Pangea#

  void searchUserWithCoolDown(String text) async {
    coolDown?.cancel();
    coolDown = Timer(
      const Duration(milliseconds: 500),
      () => searchUser(context, text),
    );
  }

  void searchUser(BuildContext context, String text) async {
    coolDown?.cancel();
    if (text.isEmpty) {
      setState(() => foundProfiles = []);
    }
    currentSearchTerm = text;
    if (currentSearchTerm.isEmpty) return;
    if (loading) return;
    setState(() => loading = true);
    final matrix = Matrix.of(context);
    SearchUserDirectoryResponse response;
    try {
      //#Pangea
      // response = await matrix.client.searchUserDirectory(text, limit: 10);
      response = await (mode == InvitationSelectionMode.admin
          ? matrix.client.searchUserDirectory(text, limit: 10)
          : eligibleStudentsAsSearchUserDirectoryResponse(
              context,
              text,
            ));
      //Pangea#
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((e).toLocalizedString(context))),
      );
      return;
    } finally {
      setState(() => loading = false);
    }
    setState(() {
      foundProfiles = List<Profile>.from(response.results);
      if (text.isValidMatrixId &&
          foundProfiles.indexWhere((profile) => text == profile.userId) == -1) {
        setState(
          () => foundProfiles = [
            Profile.fromJson({'user_id': text}),
          ],
        );
      }
      //#Pangea
      final participants = Matrix.of(context)
          .client
          .getRoomById(roomId!)
          ?.getParticipants()
          .where(
            (user) =>
                [Membership.join, Membership.invite].contains(user.membership),
          )
          .toList();
      foundProfiles.removeWhere(
        (profile) =>
            participants?.indexWhere((u) => u.id == profile.userId) != -1 &&
            BotName.byEnvironment != profile.userId,
      );
      //Pangea#
    });
  }

  //#Pangea
  Room? _room;
  Room? get room => _room ??= Matrix.of(context).client.getRoomById(roomId!);

  // request participants for all parent spaces
  Future<void> requestParentSpaceParticipants() async {
    final spaceParents = room?.pangeaSpaceParents;
    if (spaceParents != null) {
      await Future.wait([
        ...spaceParents.map((r) async {
          await r.requestParticipants();
        }),
        room!.requestParticipants(),
      ]);
    }
  }

  InvitationSelectionMode mode = InvitationSelectionMode.member;

  StreamSubscription<SyncUpdate>? _spaceSubscription;
  @override
  void initState() {
    Future.delayed(
      Duration.zero,
      () => setState(
        () => mode = room?.isSpace ?? false
            ? InvitationSelectionMode.admin
            : InvitationSelectionMode.member,
      ),
    );
    _spaceSubscription = Matrix.of(context)
        .client
        .onSync
        .stream
        .where(
          (event) =>
              event.rooms?.join?.keys.any(
                (ithRoomId) =>
                    room?.pangeaSpaceParents
                        .map((e) => e.id)
                        .contains(ithRoomId) ??
                    false,
              ) ??
              false,
        )
        .listen(
      (SyncUpdate syncUpdate) async {
        await requestParentSpaceParticipants();
        setState(() {});
      },
    );
    super.initState();
  }

  @override
  void dispose() {
    _spaceSubscription?.cancel();
    super.dispose();
  }
  //Pangea#

  @override
  Widget build(BuildContext context) => InvitationSelectionView(this);
}
