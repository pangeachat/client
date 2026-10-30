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
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      // silent-ok: a corrupt or foreign storage value reads as no entry; the
      // reader clears it.
      return null;
    }
    final id = decoded is Map<String, Object?> ? decoded['id'] : null;
    return id is String && id.isNotEmpty ? PendingInvitation(id) : null;
  }
}
