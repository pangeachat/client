import 'package:fluffychat/features/navigation/token_fields.dart';
import 'package:fluffychat/features/navigation/token_params/token_param.dart';

/// The Learning Objective (Mission) whose detail panel is open:
/// `objective:<missionId>[.c<courseRoomId>]`, the Learning Objectives list's
/// analogue of a `vocab:` construct detail. [courseId] names the course the
/// detail was opened from (#9559), so a Mission two courses share shows the
/// course the learner was looking at; without it the page picks one.
class ObjectiveTokenParam extends TokenParam {
  final String missionId;
  final String? courseId;
  const ObjectiveTokenParam({required this.missionId, this.courseId});

  static const String _courseField = 'c';

  @override
  String build() {
    final courseId = this.courseId;
    return TokenFields.join([
      TokenFields.encode(missionId),
      if (courseId != null) '$_courseField${TokenFields.encode(courseId)}',
    ]);
  }

  factory ObjectiveTokenParam.parse(String param) {
    final fields = TokenFields.split(param);
    String? courseId;
    for (final field in fields.skip(1)) {
      if (field.startsWith(_courseField)) {
        courseId = TokenFields.decode(field.substring(_courseField.length));
      }
    }
    return ObjectiveTokenParam(
      missionId: TokenFields.decode(fields.first),
      courseId: courseId,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ObjectiveTokenParam &&
      other.missionId == missionId &&
      other.courseId == courseId;

  @override
  int get hashCode => Object.hash(missionId, courseId);
}
