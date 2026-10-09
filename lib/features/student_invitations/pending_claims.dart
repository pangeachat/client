import 'dart:convert';

/// A seat invitation the visitor arrived with (`<app>/<class code>?inv=<id>`),
/// ferried across the login bounce (SpaceCodeRepo.pendingInvitation) until it
/// is confirmed after sign-in. [ackedDisclosureVersion] is set while the
/// visitor has ticked "Your teacher will manage this account" on the
/// sign-up/sign-in screen: the version of the disclosure text they saw.
class PendingInvitation {
  final String invitationId;
  final int? ackedDisclosureVersion;

  const PendingInvitation(this.invitationId, {this.ackedDisclosureVersion});

  PendingInvitation withAck(int? version) =>
      PendingInvitation(invitationId, ackedDisclosureVersion: version);

  String encode() =>
      jsonEncode({'id': invitationId, 'ack': ?ackedDisclosureVersion});

  /// Null for anything that is not an entry this class wrote.
  static PendingInvitation? decode(String raw) {
    final json = _object(raw);
    final id = json?['id'];
    final ack = json?['ack'];
    if (id is! String || id.isEmpty) return null;
    return PendingInvitation(
      id,
      ackedDisclosureVersion: ack is int ? ack : null,
    );
  }
}

/// A Canvas launch hand-off ticket (C5.1), ferried from `/lti/link` across
/// the sign-up/sign-in bounce until it is returned once after sign-in.
/// [instructor] tickets connect a Canvas course on admin-dash and carry no
/// confirmation; learner tickets need [ackedDisclosureVersion] before they
/// are sent. [courseName] is the Canvas course title from the launch,
/// display-only.
class PendingLtiTicket {
  final String ticket;
  final bool instructor;
  final String? courseName;
  final int? ackedDisclosureVersion;

  const PendingLtiTicket(
    this.ticket, {
    this.instructor = false,
    this.courseName,
    this.ackedDisclosureVersion,
  });

  PendingLtiTicket withAck(int? version) => PendingLtiTicket(
    ticket,
    instructor: instructor,
    courseName: courseName,
    ackedDisclosureVersion: version,
  );

  String encode() => jsonEncode({
    'ticket': ticket,
    'instructor': instructor,
    'course': ?courseName,
    'ack': ?ackedDisclosureVersion,
  });

  static PendingLtiTicket? decode(String raw) {
    final json = _object(raw);
    final ticket = json?['ticket'];
    if (ticket is! String || ticket.isEmpty) return null;
    final course = json?['course'];
    final ack = json?['ack'];
    return PendingLtiTicket(
      ticket,
      instructor: json?['instructor'] == true,
      courseName: course is String ? course : null,
      ackedDisclosureVersion: ack is int ? ack : null,
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
