import 'package:matrix/matrix.dart';

extension LeaveRoomExtension on Room {
  /// The responses Synapse gives `/leave` when it no longer knows the room —
  /// the state an old activity session reaches once no local user is left in
  /// it. The SDK's [leave] reads them as a leave as well: it drops the room
  /// from the local database and then rethrows anyway.
  static const _unknownRoomErrors = {
    MatrixError.M_NOT_FOUND,
    MatrixError.M_UNKNOWN,
  };

  /// [leave], counting a room the homeserver no longer knows as already left.
  ///
  /// The room is gone from the client either way, so the exception can only
  /// produce an error dialog — and a Sentry report — for work that finished
  /// (#8234). Every other failure still throws: the room is still joined, and
  /// the learner has to be told the leave did not happen.
  Future<void> leaveIgnoringUnknownRoom() async {
    try {
      await leave();
    } on MatrixException catch (e) {
      if (!_unknownRoomErrors.contains(e.error)) rethrow;
    }
  }
}
