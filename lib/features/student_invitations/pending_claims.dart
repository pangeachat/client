import 'dart:convert';

/// A seat invitation the visitor arrived with (`<app>/<class code>?inv=<id>`),
/// ferried across the login bounce (SpaceCodeRepo.pendingInvitation) until it
/// is opened once after sign-in.
class PendingInvitation {
  final String invitationId;

  const PendingInvitation(this.invitationId);

  String encode() => jsonEncode({'id': invitationId});

  /// Null for anything that is not an entry this class wrote.
  static PendingInvitation? decode(String raw) {
    final id = _object(raw)?['id'];
    return id is String && id.isNotEmpty ? PendingInvitation(id) : null;
  }
}

/// A Canvas launch hand-off ticket (C5.1), ferried from `/lti/link` across
/// the sign-up/sign-in bounce until it is returned once after sign-in.
/// [instructor] tickets connect a Canvas course on admin-dash; learner
/// tickets link the account and claim. [courseName] is the Canvas course
/// title from the launch, display-only.
class PendingLtiTicket {
  final String ticket;
  final bool instructor;
  final String? courseName;

  const PendingLtiTicket(
    this.ticket, {
    this.instructor = false,
    this.courseName,
  });

  String encode() => jsonEncode({
    'ticket': ticket,
    'instructor': instructor,
    'course': ?courseName,
  });

  static PendingLtiTicket? decode(String raw) {
    final json = _object(raw);
    final ticket = json?['ticket'];
    if (ticket is! String || ticket.isEmpty) return null;
    final course = json?['course'];
    return PendingLtiTicket(
      ticket,
      instructor: json?['instructor'] == true,
      courseName: course is String ? course : null,
    );
  }
}

Map<String, Object?>? _object(String raw) {
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map<String, Object?> ? decoded : null;
  } on FormatException {
    // silent-ok: a corrupt or foreign storage value reads as no entry; the
    // reader clears it.
    return null;
  }
}
