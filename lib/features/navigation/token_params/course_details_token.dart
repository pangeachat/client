import 'package:fluffychat/features/navigation/token_params/token_param.dart';
import 'package:fluffychat/routes/chat/chat_details/space_details_content.dart';

class CourseDetailsTokenParam extends TokenParam {
  /// The course-page section the card scrolls to, or — with [expanded] — the
  /// section whose full subpage is pushed over the card. Null is the page top.
  final SpaceSettingsTabs? activeTab;

  /// Whether the section's full subpage ("See all") is pushed within the card,
  /// riding the param as `<section>/all` per the token grammar
  /// (routing.instructions.md: pushed subpages are slash-separated).
  final bool expanded;

  const CourseDetailsTokenParam({
    required this.activeTab,
    this.expanded = false,
  });

  static const String _expandedSegment = 'all';

  @override
  String build() {
    final tab = activeTab;
    if (tab == null) return '';
    return expanded ? '${tab.name}/$_expandedSegment' : tab.name;
  }

  factory CourseDetailsTokenParam.parse(String param) {
    final segments = param.split('/');
    return CourseDetailsTokenParam(
      activeTab: segments.first.isNotEmpty
          ? SpaceSettingsTabs.fromString(segments.first)
          : null,
      expanded: segments.length > 1 && segments[1] == _expandedSegment,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CourseDetailsTokenParam &&
      other.activeTab == activeTab &&
      other.expanded == expanded;

  @override
  int get hashCode => Object.hashAll([activeTab, expanded]);
}
