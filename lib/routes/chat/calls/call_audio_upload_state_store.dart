import 'dart:convert';

import 'package:matrix/matrix.dart' show Logs;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/routes/chat/calls/call_audio_recorder.dart';

/// The durable half of [CallAudioUploadStateStore]: remembers upload/send
/// progress in `SharedPreferences`, the same store [CallBreadcrumb] uses for
/// the same reason -- a small, keyed record that has to outlive the Dart
/// isolate, not merely the retry loop that wrote it.
///
/// One key per transaction id, mirroring [CallBreadcrumb.keyFor]'s own
/// per-account keying: a call's audio half is identified by exactly the same
/// (call key, sender, device) triple its transaction id is built from, so
/// reusing that string as the storage key needs no separate index.
class SharedPreferencesCallAudioUploadStateStore
    implements CallAudioUploadStateStore {
  const SharedPreferencesCallAudioUploadStateStore();

  static String _keyFor(String txnId) => 'pangea.call_audio.upload.$txnId';

  @override
  Future<Map<String, dynamic>?> read(String txnId) async {
    try {
      final store = await SharedPreferences.getInstance();
      final raw = store.getString(_keyFor(txnId));
      if (raw == null) return null;
      final json = jsonDecode(raw);
      // Somebody else's bytes, in principle -- a future app version writing
      // a shape this one does not expect. Read as "nothing usable" rather
      // than thrown, on the same terms [CallBreadcrumb.read] treats a
      // malformed record: a durable cache that cannot be trusted is no
      // worse than an empty one, and it must not take the send down with it.
      return json is Map<String, dynamic> ? json : null;
    } catch (e, s) {
      Logs().w('Could not read the persisted call-audio upload state', e, s);
      return null;
    }
  }

  @override
  Future<void> write(String txnId, Map<String, dynamic> state) async {
    try {
      final store = await SharedPreferences.getInstance();
      await store.setString(_keyFor(txnId), jsonEncode(state));
    } catch (e, s) {
      Logs().w('Could not persist the call-audio upload state', e, s);
    }
  }
}
