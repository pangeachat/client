/// The `pangea.course_plan` room state event: which quest a course space is
/// running, and the target language the public course catalog filters on.
///
/// See `public-courses.instructions.md` in synapse-pangea-chat for the rule
/// this event feeds — a room is a course if, and only if, it is published and
/// carries one of these with a usable plan id.
class CoursePlanEvent {
  final String uuid;

  /// Target language of the course. Null on spaces created before the language
  /// was recorded in room state; the catalog returns those unfiltered but
  /// excludes them when a language filter is applied.
  final String? l2;

  /// The course's affiliated institution, set by its teacher in the admin
  /// dashboard; shown on the course's card. Null when none was set.
  final String? institution;

  CoursePlanEvent({required this.uuid, this.l2, this.institution});

  Map<String, dynamic> toJson() => {
    'uuid': uuid,
    if (l2 != null) 'l2': l2,
    if (institution != null) 'institution': institution,
  };

  /// Returns null when the event carries no usable plan id, so a malformed or
  /// blanked event reads as "this room has no course plan" — the same answer a
  /// room with no event at all gives — instead of throwing at the call site.
  ///
  /// Spaces created server-side write the id as `course_plan_id` rather than
  /// `uuid`; both are accepted, matching the catalog query.
  static CoursePlanEvent? tryParse(Map<String, dynamic> json) {
    final id = _planId(json);
    if (id == null) return null;
    final l2 = json['l2'];
    final institution = json['institution'];
    return CoursePlanEvent(
      uuid: id,
      l2: l2 is String && l2.isNotEmpty ? l2 : null,
      institution: institution is String && institution.trim().isNotEmpty
          ? institution.trim()
          : null,
    );
  }

  static String? _planId(Map<String, dynamic> json) {
    for (final key in const ['uuid', 'course_plan_id']) {
      final value = json[key];
      if (value is String && value.isNotEmpty) return value;
    }
    return null;
  }
}
