import 'package:collection/collection.dart';

import 'package:fluffychat/features/navigation/token_fields.dart';
import 'package:fluffychat/features/navigation/token_params/token_param.dart';

class RoomSubpageTokenParam extends TokenParam {
  final String subpage;
  final String? filter;
  final String? courseId;

  const RoomSubpageTokenParam({
    required this.subpage,
    this.filter,
    this.courseId,
  });

  @override
  String build() {
    final filter = this.filter;
    final courseId = this.courseId;
    return TokenFields.join([
      TokenFields.encode(subpage),
      if (filter != null && filter.isNotEmpty) 'f${TokenFields.encode(filter)}',
      if (courseId != null && courseId.isNotEmpty)
        'c${TokenFields.encode(courseId)}',
    ]);
  }

  factory RoomSubpageTokenParam.parse(String param) {
    final segments = TokenFields.split(param);
    final subpage = segments.first;
    final remaining = segments.skip(1);

    final filter = remaining
        .firstWhereOrNull((r) => r.startsWith('f'))
        ?.substring(1);

    final courseId = remaining
        .firstWhereOrNull((r) => r.startsWith('c'))
        ?.substring(1);

    return RoomSubpageTokenParam(
      subpage: subpage,
      filter: filter != null && filter.isNotEmpty
          ? TokenFields.decode(filter)
          : null,
      courseId: courseId != null && courseId.isNotEmpty
          ? TokenFields.decode(courseId)
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RoomSubpageTokenParam &&
      other.subpage == subpage &&
      other.filter == filter &&
      other.courseId == courseId;

  @override
  int get hashCode => Object.hash(subpage, filter, courseId);
}
