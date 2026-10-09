import 'dart:convert';

import 'package:http/http.dart' as http;

/// The Synapse module routes the student side calls (C2 S1/S2/H1/H2, C5 L1).
///
/// Bodies stay out of every error and log: a confirm or link body carries an
/// invitation id or a single-use Canvas ticket, and the hint carries a masked
/// email. A failure surfaces as [StudentInvitationApiException] with the
/// status and the module's errcode only.
class StudentInvitationApi {
  final http.Client httpClient;
  final Uri homeserver;

  const StudentInvitationApi({
    required this.httpClient,
    required this.homeserver,
  });

  static const String _prefix = '_synapse/client/pangea/v1';

  /// H1 — the course name and masked invited address, no token.
  Future<InvitationHint> hint(String invitationId) async {
    final json = await _send(
      'GET',
      'student_invitations/hint',
      query: {'invitation_id': invitationId},
    );
    return InvitationHint(
      courseName: _nonEmpty(json['course_name']),
      maskedEmailHint: _nonEmpty(json['masked_email_hint']),
    );
  }

  /// H2 — the managed-account disclosure shown under every checkbox.
  Future<ManagedDisclosure> disclosure() async {
    final json = await _send('GET', 'managed_disclosure');
    final version = json['version'];
    final text = json['text'];
    if (version is! int || text is! String || text.isEmpty) {
      throw const StudentInvitationApiException(200, 'M_BAD_JSON');
    }
    return ManagedDisclosure(version: version, text: text);
  }

  /// S1 — confirm an invitation with the disclosure version the student saw.
  Future<ConfirmOutcome> confirm({
    required String accessToken,
    required String invitationId,
    required int disclosureVersion,
  }) async {
    final json = await _send(
      'POST',
      'student_invitations/confirm',
      accessToken: accessToken,
      body: {
        'invitation_id': invitationId,
        'disclosure_version': disclosureVersion,
      },
    );
    return switch (json['result']) {
      'claimed' => ConfirmOutcome.claimed,
      'pending_approval' => ConfirmOutcome.pendingApproval,
      'denied' => ConfirmOutcome.denied,
      _ => throw const StudentInvitationApiException(200, 'M_BAD_JSON'),
    };
  }

  /// S2 — live invitations to one of the caller's verified addresses that
  /// the caller has not confirmed.
  Future<List<PendingInvitationSummary>> minePending({
    required String accessToken,
  }) async {
    final json = await _send(
      'GET',
      'student_invitations/mine/pending',
      accessToken: accessToken,
    );
    final rows = json['invitations'];
    if (rows is! List) {
      throw const StudentInvitationApiException(200, 'M_BAD_JSON');
    }
    return [
      for (final row in rows)
        if (row is Map && row['invitation_id'] is String)
          PendingInvitationSummary(
            invitationId: row['invitation_id'] as String,
            courseName: _nonEmpty(row['course_name']),
          ),
    ];
  }

  /// L1 — return a Canvas link ticket. A learner ticket carries the
  /// confirmation ([disclosureVersion]); an instructor ticket carries nothing
  /// else. [accessToken] is the account's own token after sign-in; null only
  /// for the attempt the link page makes signed out, which a ticket bound to
  /// an already-linked account answers with a login token (an unbound ticket
  /// answers 401 and is not consumed).
  Future<LtiLinkOutcome> ltiLink({
    required String? accessToken,
    required String ticket,
    int? disclosureVersion,
  }) async {
    final json = await _send(
      'POST',
      'lti/link',
      accessToken: accessToken,
      body: {
        'ticket': ticket,
        if (disclosureVersion != null) ...{
          'confirmed': true,
          'disclosure_version': disclosureVersion,
        },
      },
    );
    final connect = json['connect_url'];
    final login = json['login_token'];
    return LtiLinkOutcome(
      connectUrl: connect is String ? Uri.tryParse(connect) : null,
      loginToken: login is String && login.isNotEmpty ? login : null,
    );
  }

  Future<Map<String, Object?>> _send(
    String method,
    String path, {
    String? accessToken,
    Map<String, String>? query,
    Map<String, Object?>? body,
  }) async {
    final url = homeserver.replace(
      path: '${homeserver.path.replaceAll(RegExp(r'/$'), '')}/$_prefix/$path',
      queryParameters: query,
    );
    final request = http.Request(method, url)
      ..headers['accept'] = 'application/json';
    if (accessToken != null) {
      request.headers['authorization'] = 'Bearer $accessToken';
    }
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final http.Response response;
    try {
      response = await http.Response.fromStream(await httpClient.send(request));
    } on Exception {
      // A transport failure's message names the URL, which can carry an
      // invitation id: report the failure, not the message.
      throw const StudentInvitationApiException(0, 'M_CONNECTION_FAILED');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      // A non-JSON body (a proxy error page) is a failure: thrown below.
      decoded = null;
    }
    final json = decoded is Map<String, Object?> ? decoded : null;
    if (response.statusCode != 200 || json == null) {
      final errcode = json?['errcode'];
      throw StudentInvitationApiException(
        response.statusCode,
        errcode is String ? errcode : null,
      );
    }
    return json;
  }

  static String? _nonEmpty(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;
}

/// A refused or failed module call: the HTTP status (0 when the request never
/// got an answer) and the module's errcode, never the body.
class StudentInvitationApiException implements Exception {
  final int statusCode;
  final String? errcode;

  const StudentInvitationApiException(this.statusCode, this.errcode);

  static const String disclosureOutdated = 'ORG.PANGEA.DISCLOSURE_OUTDATED';
  static const String alreadyClaimedInCourse =
      'ORG.PANGEA.ALREADY_CLAIMED_IN_COURSE';
  static const String ticketInvalid = 'ORG.PANGEA.TICKET_INVALID';
  static const String ticketWrongAccount = 'ORG.PANGEA.TICKET_WRONG_ACCOUNT';
  static const String ltiAlreadyLinked = 'ORG.PANGEA.LTI_ALREADY_LINKED';

  bool get isDisclosureOutdated =>
      statusCode == 409 && errcode == disclosureOutdated;

  @override
  String toString() =>
      'StudentInvitationApiException($statusCode, ${errcode ?? 'no errcode'})';
}

class InvitationHint {
  final String? courseName;
  final String? maskedEmailHint;

  const InvitationHint({this.courseName, this.maskedEmailHint});
}

class ManagedDisclosure {
  final int version;

  /// The CONTROLS-SPEC §8 text with the literal `{course}` placeholder.
  final String text;

  const ManagedDisclosure({required this.version, required this.text});

  String textFor(String courseName) => text.replaceAll('{course}', courseName);
}

enum ConfirmOutcome { claimed, pendingApproval, denied }

class PendingInvitationSummary {
  final String invitationId;
  final String? courseName;

  const PendingInvitationSummary({required this.invitationId, this.courseName});
}

class LtiLinkOutcome {
  /// Set for an instructor ticket: admin-dash's `canvas-connect` page.
  final Uri? connectUrl;

  /// Set only for a bound learner ticket sent without a token.
  final String? loginToken;

  const LtiLinkOutcome({this.connectUrl, this.loginToken});
}
