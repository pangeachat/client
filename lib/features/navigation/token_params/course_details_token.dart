import 'package:fluffychat/features/navigation/token_params/token_param.dart';
import 'package:fluffychat/routes/chat/chat_details/space_details_content.dart';

class CourseDetailsTokenParam extends TokenParam {
  final SpaceSettingsTabs? activeTab;
  const CourseDetailsTokenParam({required this.activeTab}) : super('course');

  @override
  String build() => activeTab?.name ?? '';

  factory CourseDetailsTokenParam.parse(String param) =>
      CourseDetailsTokenParam(
        activeTab: param.isNotEmpty
            ? SpaceSettingsTabs.fromString(param)
            : null,
      );

  @override
  bool operator ==(Object other) =>
      other is CourseDetailsTokenParam &&
      other.type == type &&
      other.activeTab == activeTab;

  @override
  int get hashCode => Object.hash(type, activeTab);
}
