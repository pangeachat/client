import 'package:fluffychat/pangea/common/utils/search_text.dart';

/// The course field a Courses hub search matched. Results rank in this
/// order, strongest first (#9207).
enum CourseSearchField { title, description, level }

/// What a Courses hub search reads from one course: the text its tile shows.
class CourseSearchText {
  final String title;
  final String description;

  /// The tile's CEFR level title in the app language (e.g. "Novice Mid
  /// (A1)"), or null until the course's quest outline resolves — the tile
  /// shows no level until then either.
  final String? level;

  const CourseSearchText({
    required this.title,
    required this.description,
    this.level,
  });

  /// The strongest field matching [normalizedQuery], which must already be
  /// [SearchTextUtil.normalize]d; null when none does.
  CourseSearchField? strongestMatch(String normalizedQuery) {
    if (_contains(title, normalizedQuery)) return CourseSearchField.title;
    if (_contains(description, normalizedQuery)) {
      return CourseSearchField.description;
    }
    final level = this.level;
    if (level != null && _contains(level, normalizedQuery)) {
      return CourseSearchField.level;
    }
    return null;
  }

  static bool _contains(String text, String normalizedQuery) =>
      SearchTextUtil.normalize(text).contains(normalizedQuery);

  /// [courses] narrowed to those matching [query]: title matches first, then
  /// description matches, then level matches, each keeping [courses]' order.
  /// A blank query matches everything.
  static List<T> rank<T>(
    List<T> courses,
    String query,
    CourseSearchText Function(T course) searchTextOf,
  ) {
    final normalizedQuery = SearchTextUtil.normalize(query.trim());
    if (normalizedQuery.isEmpty) return courses;

    final byField = {
      for (final field in CourseSearchField.values) field: <T>[],
    };
    for (final course in courses) {
      final field = searchTextOf(course).strongestMatch(normalizedQuery);
      if (field != null) byField[field]!.add(course);
    }
    return [for (final field in CourseSearchField.values) ...byField[field]!];
  }
}
