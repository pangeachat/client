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
  final String? initialLanguageFilter;

  const RoomSubpageTokenParam({
    required this.subpage,
    this.inviteFilter,
    this.courseId,
    this.initialLanguageFilter,
  });

  @override
  bool get isPushed => subpage == RoomSubpageEnum.addcourse && courseId != null;

  @override
  RoomSubpageTokenParam? get poppedParam => isPushed
      ? RoomSubpageTokenParam(
          subpage: subpage,
          initialLanguageFilter: initialLanguageFilter,
        )
      : null;

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
        final languageFilter = initialLanguageFilter;
        if (courseId == null) {
          return TokenFields.join([
            encodedSubpage,
            if (languageFilter != null && languageFilter.isNotEmpty)
              'l${TokenFields.encode(languageFilter)}',
          ]);
        }
        return TokenFields.join([
          '$encodedSubpage/${TokenFields.encode(courseId)}',
          if (languageFilter != null && languageFilter.isNotEmpty)
            'l${TokenFields.encode(languageFilter)}',
        ]);
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
        if (parts.length < 2) {
          final languageEntry = chunks
              .skip(1)
              .firstWhereOrNull((c) => c.startsWith('l'))
              ?.substring(1);
          return RoomSubpageTokenParam(
            subpage: subpage,
            initialLanguageFilter:
                languageEntry != null && languageEntry.isNotEmpty
                ? TokenFields.decode(languageEntry)
                : null,
          );
        }

        final courseChunks = TokenFields.split(parts[1]);
        final courseId = TokenFields.decode(courseChunks[0]);
        final languageEntry = courseChunks
            .skip(1)
            .firstWhereOrNull((c) => c.startsWith('l'))
            ?.substring(1);

        return RoomSubpageTokenParam(
          subpage: subpage,
          courseId: courseId,
          initialLanguageFilter:
              languageEntry != null && languageEntry.isNotEmpty
              ? TokenFields.decode(languageEntry)
              : null,
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
      other.courseId == courseId &&
      other.initialLanguageFilter == initialLanguageFilter;

  @override
  int get hashCode =>
      Object.hash(subpage, inviteFilter, courseId, initialLanguageFilter);
}
