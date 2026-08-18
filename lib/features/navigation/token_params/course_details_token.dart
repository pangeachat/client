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

  /// The sections with a full "See all" subpage. `more` shows everything
  /// inline and `analytics` is retired, so an expanded token for either
  /// degrades to the plain section scroll — and is NOT pushed.
  static const Set<SpaceSettingsTabs> expandableSections = {
    SpaceSettingsTabs.course,
    SpaceSettingsTabs.chat,
    SpaceSettingsTabs.participants,
  };

  /// The pushed subpage this token opens, or null when it opens the plain
  /// card (no section, a non-expandable section, or not expanded).
  SpaceSettingsTabs? get expandedSection {
    final tab = activeTab;
    if (tab == null || !expanded) return null;
    return expandableSections.contains(tab) ? tab : null;
  }

  /// `<section>/all` is a pushed subpage, so the panel's close control renders
  /// the back arrow and pops it — the page renders no navigation of its own
  /// (the close-affordance rule, routing.instructions.md). Gated on
  /// [expandedSection] so the arrow can't show over a card that isn't pushed.
  @override
  bool get isPushed => expandedSection != null;

  @override
  CourseDetailsTokenParam? get poppedParam =>
      isPushed ? CourseDetailsTokenParam(activeTab: activeTab) : null;

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
      // Exactly `<section>/all`: a trailing segment is malformed, not a push.
      expanded: segments.length == 2 && segments[1] == _expandedSegment,
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
