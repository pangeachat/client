import 'package:matrix/matrix.dart';

/// A read the CMS refused because our Matrix access token is no longer one the
/// homeserver accepts — the session expired, was refreshed out from under the
/// request, or was invalidated elsewhere (another device logged it out, the
/// password changed).
///
/// This is a **token-lifecycle** state, not a permission bug: the learner was
/// never forbidden the resource, we simply presented credentials the server had
/// already retired. It exists as its own type because the CMS cannot say so
/// itself — see [matrixTokenRejected].
class SessionExpiredException implements Exception {
  @override
  String toString() =>
      'SessionExpiredException: the homeserver rejected our Matrix access token';
}

/// The errcodes by which a homeserver states the access token we presented is
/// no longer usable, as opposed to the request being wrong. Kept in one place
/// because these four are the whole vocabulary for "your token is dead":
/// `M_UNKNOWN_TOKEN` (unknown/retired session), `M_MISSING_TOKEN` (never
/// arrived), `M_FORBIDDEN` (expired or invalidated) and `M_USER_DEACTIVATED`
/// (the account is gone) — see the Common Errors table in
/// `matrix-auth.instructions.md`.
const Set<String> kRejectedTokenErrcodes = {
  'M_UNKNOWN_TOKEN',
  'M_MISSING_TOKEN',
  'M_FORBIDDEN',
  'M_USER_DEACTIVATED',
};

/// Whether [errcode] is the homeserver stating our token is dead.
bool isRejectedTokenErrcode(String? errcode) =>
    errcode != null && kRejectedTokenErrcodes.contains(errcode);

/// Whether the homeserver **positively rejects** the token [client] currently
/// holds, asked over the very endpoint the CMS validates against
/// (`/_matrix/client/v3/account/whoami`).
///
/// Why this exists: Payload answers *both* "you are not authenticated" and "you
/// are authenticated but not permitted" with the same **403** and the same
/// body, `{"errors":[{"message":"You are not allowed to perform this
/// action."}]}` — there is no 401 anywhere in the CMS surface. So a 403 alone
/// cannot tell a dead session apart from a genuine permission bug, and the
/// client's severity policy (403 → error, "a code bug") mis-reads the first as
/// the second. Re-asking whoami is the discriminator, and it is decisive
/// because it is the same question the CMS asked.
///
/// **Deliberately conservative.** Only an explicit rejection
/// ([isRejectedTokenErrcode]) returns true. A success, a network failure, or
/// any other exception returns false, so the caller falls through to its normal
/// classification. A real permission bug can therefore never be reclassified
/// into a session problem by a flaky probe — the failure mode is "still
/// reported as an error", which is the safe direction.
///
/// Costs one request, on an already-failing path only.
Future<bool> matrixTokenRejected(Client client) async {
  try {
    await client.getTokenOwner();
    return false;
  } on MatrixException catch (e) {
    return isRejectedTokenErrcode(e.errcode);
  } catch (_) {
    return false;
  }
}
