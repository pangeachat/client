import 'package:collection/collection.dart';

import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/token_fields.dart';
import 'package:fluffychat/features/navigation/token_params/token_param.dart';

class AddCourseTokenParam extends TokenParam {
  final String? subpage;
  final String? roomId;
  final String? courseId;
  final String? targetLanguage;
  final String? joinCode;
  final bool invite;

  const AddCourseTokenParam({
    this.subpage,
    this.roomId,
    this.courseId,
    this.targetLanguage,
    this.joinCode,
    this.invite = false,
  });

  @override
  String build() {
    final subpage = this.subpage;
    final roomId = this.roomId;
    final courseId = this.courseId;
    final targetLanguage = this.targetLanguage;
    final joinCode = this.joinCode;

    return TokenFields.join([
      if (subpage != null) TokenFields.encode(subpage),
      if (roomId != null) 'r${TokenFields.encode(shortRoomId(roomId))}',
      if (courseId != null) 'c${TokenFields.encode(courseId)}',
      if (targetLanguage != null) 'l${TokenFields.encode(targetLanguage)}',
      if (joinCode != null) 'j${TokenFields.encode(joinCode)}',
      if (invite) 'i',
    ]);
  }

  factory AddCourseTokenParam.parse(String param) {
    final parts = TokenFields.split(param);
    final subpage = TokenFields.decode(parts.first);

    if (parts.length <= 1) {
      return AddCourseTokenParam(subpage: subpage);
    }

    final filters = parts.skip(1);

    final roomIdEntry = filters
        .firstWhereOrNull((f) => f.startsWith('r'))
        ?.substring(1);

    final courseIdEntry = filters
        .firstWhereOrNull((f) => f.startsWith('c'))
        ?.substring(1);

    final targetLanguageEntry = filters
        .firstWhereOrNull((f) => f.startsWith('l'))
        ?.substring(1);

    final joinCodeEntry = filters
        .firstWhereOrNull((f) => f.startsWith('j'))
        ?.substring(1);

    final inviteEntry = filters.firstWhereOrNull((f) => f == 'i');

    return AddCourseTokenParam(
      subpage: subpage,
      roomId: roomIdEntry != null && roomIdEntry.isNotEmpty
          ? TokenFields.decode(roomIdEntry)
          : null,
      courseId: courseIdEntry != null && courseIdEntry.isNotEmpty
          ? TokenFields.decode(courseIdEntry)
          : null,
      targetLanguage:
          targetLanguageEntry != null && targetLanguageEntry.isNotEmpty
          ? TokenFields.decode(targetLanguageEntry)
          : null,
      joinCode: joinCodeEntry != null && joinCodeEntry.isNotEmpty
          ? TokenFields.decode(joinCodeEntry)
          : null,
      invite: inviteEntry != null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AddCourseTokenParam &&
      other.subpage == subpage &&
      other.roomId == roomId &&
      other.courseId == courseId &&
      other.targetLanguage == targetLanguage &&
      other.joinCode == joinCode &&
      other.invite == invite;

  @override
  int get hashCode =>
      Object.hash(subpage, roomId, courseId, targetLanguage, joinCode, invite);
}
