import 'dart:convert';

import 'package:http/http.dart' as http;

/// The Synapse module routes the student side calls (C2 open and H1, C5 L1).
///
/// Bodies stay out of every error and log: an open or link body carries an
/// invitation id or a single-use Canvas ticket, and the hint carries a masked
/// email. A failure surfaces as [StudentInvitationApiException] with the
/// status and the module's errcode only.
class StudentInvitationApi {
  final http.Client httpClient;
  final Uri homeserver;

  /// Each call's bound. The app's Matrix HTTP client waits up to 30 minutes
  /// (long sync polls), far too long for a sign-in step to hang on.
  final Duration requestTimeout;

  const StudentInvitationApi({
    required this.httpClient,
    required this.homeserver,
    this.requestTimeout = const Duration(seconds: 30),
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

  /// Open an invitation as the signed-in student (`POST …/{id}/open`, body
  /// `{}`; idempotent server-side). It claims at once when the account has
  /// the invited address verified; otherwise it records a request for the
  /// teacher to grant.
  Future<({OpenOutcome outcome, String? roomId})> open({
    required String accessToken,
    required String invitationId,
  }) async {
    final json = await _send(
      'POST',
      'student_invitations/${Uri.encodeComponent(invitationId)}/open',
      accessToken: accessToken,
      body: const {},
    );
    final outcome = switch (json['result']) {
      'claimed' => OpenOutcome.claimed,
      'pending' || 'pending_approval' => OpenOutcome.pending,
      'denied' => OpenOutcome.denied,
      _ => throw const StudentInvitationApiException(200, 'M_BAD_JSON'),
    };
    final roomId = json['room_id'];
    return (outcome: outcome, roomId: roomId is String ? roomId : null);
  }

  /// L1 — return a Canvas link ticket (body: just the ticket). [accessToken]
  /// is the account's own token after sign-in; null only for the attempt the
  /// link page makes signed out, which a ticket bound to an already-linked
  /// account answers with a login token (an unbound ticket answers 401 and
  /// is not consumed).
  Future<LtiLinkOutcome> ltiLink({
    required String? accessToken,
    required String ticket,
  }) async {
    final json = await _send(
      'POST',
      'lti/link',
      accessToken: accessToken,
      body: {'ticket': ticket},
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
      response = await httpClient
          .send(request)
          .then(http.Response.fromStream)
          .timeout(requestTimeout);
    } on Exception {
      // A transport failure or timeout: its message names the URL, which can
      // carry an invitation id, so report the failure, not the message.
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

  static const String alreadyClaimedInCourse =
      'ORG.PANGEA.ALREADY_CLAIMED_IN_COURSE';
  static const String ticketInvalid = 'ORG.PANGEA.TICKET_INVALID';
  static const String ticketWrongAccount = 'ORG.PANGEA.TICKET_WRONG_ACCOUNT';
  static const String ltiAlreadyLinked = 'ORG.PANGEA.LTI_ALREADY_LINKED';

  @override
  String toString() =>
      'StudentInvitationApiException($statusCode, ${errcode ?? 'no errcode'})';
}

class InvitationHint {
  final String? courseName;
  final String? maskedEmailHint;

  const InvitationHint({this.courseName, this.maskedEmailHint});
}

enum OpenOutcome { claimed, pending, denied }

class LtiLinkOutcome {
  /// Set for an instructor ticket: admin-dash's `canvas-connect` page.
  final Uri? connectUrl;

  /// Set only for a bound learner ticket sent without a token.
  final String? loginToken;

  const LtiLinkOutcome({this.connectUrl, this.loginToken});
}
