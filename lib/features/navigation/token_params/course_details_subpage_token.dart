import 'package:fluffychat/features/navigation/token_fields.dart';
import 'package:fluffychat/features/navigation/token_params/token_param.dart';

class CourseDetailsSubpageTokenParam extends TokenParam {
  final String page;
  final String? filter;

  const CourseDetailsSubpageTokenParam({required this.page, this.filter})
    : super('coursepage');

  @override
  String build() {
    final filter = this.filter;
    return TokenFields.join([
      TokenFields.encode(page),
      if (filter != null) TokenFields.encode(filter),
    ]);
  }

  factory CourseDetailsSubpageTokenParam.parse(String param) {
    final segments = TokenFields.split(param);
    final filter = segments.length > 1 ? TokenFields.decode(segments[1]) : null;
    return CourseDetailsSubpageTokenParam(page: segments.first, filter: filter);
  }

  @override
  bool operator ==(Object other) =>
      other is CourseDetailsSubpageTokenParam &&
      other.type == type &&
      other.page == page &&
      other.filter == filter;

  @override
  int get hashCode => Object.hash(type, page, filter);
}
