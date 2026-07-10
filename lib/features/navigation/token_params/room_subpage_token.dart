import 'package:collection/collection.dart';

import 'package:fluffychat/features/navigation/token_fields.dart';
import 'package:fluffychat/features/navigation/token_params/room_token.dart';
import 'package:fluffychat/features/navigation/token_params/token_param.dart';
import 'package:fluffychat/routes/chat/chat_details/invite/pangea_invitation_selection.dart';

enum RoomSubpageEnum {
  edit,
  invite,
  access,
  permissions,
  emotes,
  addcourse;

  static RoomSubpageEnum? fromString(String value) =>
      RoomSubpageEnum.values.firstWhereOrNull((v) => v.name == value);
}

class RoomSubpageTokenParam extends TokenParam {
  final RoomSubpageEnum? subpage;
  final InvitationFilter? inviteFilter;
  final String? courseId;

  const RoomSubpageTokenParam({
    required this.subpage,
    this.inviteFilter,
    this.courseId,
  });

  @override
  bool get isPushed => subpage == RoomSubpageEnum.addcourse && courseId != null;

  @override
  RoomSubpageTokenParam? get poppedParam =>
      isPushed ? RoomSubpageTokenParam(subpage: subpage) : null;

  @override
  String build() {
    final subpage = this.subpage;
    if (subpage == null) return '';

    final encodedSubpage = TokenFields.encode(subpage.name);
    switch (subpage) {
      case RoomSubpageEnum.edit:
      case RoomSubpageEnum.access:
      case RoomSubpageEnum.permissions:
      case RoomSubpageEnum.emotes:
        return encodedSubpage;
      case RoomSubpageEnum.invite:
        final filter = inviteFilter;
        return TokenFields.join([
          encodedSubpage,
          if (filter != null) 'f${TokenFields.encode(filter.name)}',
        ]);
      case RoomSubpageEnum.addcourse:
        final courseId = this.courseId;
        if (courseId == null) return encodedSubpage;
        return '$encodedSubpage/${TokenFields.encode(courseId)}';
    }
  }

  factory RoomSubpageTokenParam.parse(String param) {
    final remaining = param.startsWith('details/')
        ? param.substring('details/'.length)
        : param;

    final parts = remaining.split('/');
    final chunks = TokenFields.split(parts.first);
    final subpage = RoomSubpageEnum.fromString(
      TokenFields.decode(chunks.first),
    );

    if (subpage == null) {
      return RoomSubpageTokenParam(subpage: subpage);
    }

    switch (subpage) {
      case RoomSubpageEnum.edit:
      case RoomSubpageEnum.access:
      case RoomSubpageEnum.permissions:
      case RoomSubpageEnum.emotes:
        return RoomSubpageTokenParam(subpage: subpage);
      case RoomSubpageEnum.invite:
        return RoomSubpageTokenParam(
          subpage: subpage,
          inviteFilter: chunks.length > 1
              ? InvitationFilter.fromString(
                  TokenFields.decode(chunks[1].substring(1)),
                )
              : null,
        );
      case RoomSubpageEnum.addcourse:
        return RoomSubpageTokenParam(
          subpage: subpage,
          courseId: parts.length > 1 ? TokenFields.decode(parts[1]) : null,
        );
    }
  }

  factory RoomSubpageTokenParam.fromRoomParam(RoomTokenParam param) {
    try {
      final subpageEntry = param.subpage;
      if (subpageEntry == null) {
        return RoomSubpageTokenParam(subpage: null, inviteFilter: param.filter);
      }

      final parts = subpageEntry.split('/');
      final remaining = parts.length > 1 && parts[0] == 'details'
          ? parts.skip(1)
          : parts;

      final subpage = RoomSubpageEnum.fromString(remaining.first);
      return RoomSubpageTokenParam(
        subpage: subpage,
        inviteFilter: param.filter,
      );
    } catch (e) {
      return RoomSubpageTokenParam(subpage: null, inviteFilter: param.filter);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is RoomSubpageTokenParam &&
      other.subpage == subpage &&
      other.inviteFilter == inviteFilter &&
      other.courseId == courseId;

  @override
  int get hashCode => Object.hash(subpage, inviteFilter, courseId);
}
