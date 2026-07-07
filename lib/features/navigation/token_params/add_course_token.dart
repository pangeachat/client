import 'package:collection/collection.dart';

import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/token_fields.dart';
import 'package:fluffychat/features/navigation/token_params/token_param.dart';

class AddCourseTokenParam extends TokenParam {
  final String subpage;
  final String? roomId;
  final String? courseId;
  final String? targetLanguage;
  final bool invite;

  const AddCourseTokenParam({
    required this.subpage,
    this.roomId,
    this.courseId,
    this.targetLanguage,
    this.invite = false,
  }) : super('addcourse');

  @override
  String build() {
    final roomId = this.roomId;
    final courseId = this.courseId;
    final targetLanguage = this.targetLanguage;

    return TokenFields.join([
      TokenFields.encode(subpage),
      if (roomId != null) 'r${TokenFields.encode(shortRoomId(roomId))}',
      if (courseId != null) 'c${TokenFields.encode(courseId)}',
      if (targetLanguage != null) 'l${TokenFields.encode(targetLanguage)}',
      if (invite) 'i',
    ]);
  }

  factory AddCourseTokenParam.parse(String param) {
    final parts = TokenFields.split(param);
    final subpage = parts.first;
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
      invite: inviteEntry != null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AddCourseTokenParam &&
      other.type == type &&
      other.subpage == subpage &&
      other.targetLanguage == targetLanguage;

  @override
  int get hashCode => Object.hash(type, subpage, targetLanguage);
}
