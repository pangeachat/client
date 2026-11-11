import 'package:fluffychat/routes/chat/calls/call_audio_pending_store.dart';

/// IndexedDB exists only on the web, the one platform that asks for it.
PendingCallAudioRows indexedDbPendingCallAudioRows() =>
    throw UnsupportedError('IndexedDB is web only');
