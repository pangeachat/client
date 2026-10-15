import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/features/analytics/constructs_upload_result.dart';
import 'package:fluffychat/features/analytics/listening_exposure_buffer.dart';
import 'package:fluffychat/features/analytics/saved_analytics_extension.dart';
import 'package:fluffychat/features/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/features/analytics_data/analytics_database.dart';
import 'package:fluffychat/features/analytics_data/analytics_settings_extension.dart';
import 'package:fluffychat/features/analytics_data/analytics_update_dispatcher.dart';
import 'package:fluffychat/features/analytics_data/server_event_arrivals.dart';
import 'package:fluffychat/features/connection_status/connection_status_controller.dart';
import 'package:fluffychat/features/dosage/dosage_audio_buffer.dart';
import 'package:fluffychat/features/dosage/dosage_engagement_tracker.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/pangea/lemmas/user_lemma_info_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';

class AnalyticsUpdateService with WidgetsBindingObserver {
  static const int _maxMessagesCached = 10;

  /// How long a flush waits for the server's copy of what it sent before
  /// clearing the sent batches anyway. A sync that carries new events returns
  /// at once, so this only runs out on a stalled connection.
  static const Duration _serverCopyTimeout = Duration(seconds: 30);

  final AnalyticsDataService dataService;

  /// Test-only injected tracker; when set, [dispose] flushes it directly instead
  /// of the per-account registry.
  final DosageEngagementTracker? _injectedTracker;

  AnalyticsUpdateService(
    this.dataService, {
    DosageEngagementTracker? tracker,
    DosageAudioBuffer? audioBuffer,
    ValueListenable<ConnectionStatus>? connectionStatus,
  }) : _injectedTracker = tracker,
       _injectedAudioBuffer = audioBuffer,
       _connectionStatus =
           connectionStatus ?? ConnectionStatusController.instance.status {
    // Pin the account mxid AT CONSTRUCTION when the client is already logged in.
    // The authoritative pin is [pinAccountId] called from
    // [AnalyticsDataService._initDatabase] the moment `loggedIn` is observed
    // (before the fallible analytics init); this and [start] are backstops.
    pinAccountId();
  }

  /// The account mxid, PINNED the moment the client is logged in (from
  /// [AnalyticsDataService._initDatabase], before the fallible analytics init;
  /// with construction + [start] as backstops) and retained — so teardown
  /// resolves it even after the SDK nulls userID in `clear()` ahead of
  /// `loggedOut`, and even when the analytics init fails before `start`. Not a
  /// raw constructor snapshot (that can precede login on a fresh startup with an
  /// unlogged default client); falls back to a live read until pinned.
  String? _pinnedAccountId;
  String get _accountUserId =>
      _pinnedAccountId ?? dataService.accountUserId ?? '';

  /// Latches the account mxid from the live account id when one is available.
  /// Idempotent; a no-op before login. Called at the earliest logged-in point.
  void pinAccountId() {
    final live = dataService.accountUserId;
    if (live != null && live.isNotEmpty) _pinnedAccountId = live;
  }

  /// This account's engagement tracker (heartbeat/background flush target).
  DosageEngagementTracker? get _tracker =>
      _injectedTracker ?? DosageEngagementTracker.forAccount(_accountUserId);

  /// This account's audio-signal buffer. It rides the SAME three hooks as the
  /// engagement tracker — the 5-minute heartbeat, any move off `resumed`, and
  /// teardown — rather than owning a timer of its own. One lifecycle means the
  /// coverage period, which must be declared whether or not audio occurred, can
  /// never drift out of step with the events it covers.
  DosageAudioBuffer? get _audioBuffer =>
      _injectedAudioBuffer ?? DosageAudioBuffer.forAccount(_accountUserId);

  /// Test-only injected audio buffer; when set, teardown drains it directly
  /// instead of going through the per-account registry.
  final DosageAudioBuffer? _injectedAudioBuffer;

  /// Flushes the audio buffer against this account's live bearer. Fire-and-
  /// forget on the heartbeat and lifecycle paths; awaited only on teardown.
  Future<void> _flushAudio({bool drainAll = false}) =>
      _audioBuffer?.flush(
        drainAll: drainAll,
        accessToken: dataService.accountAccessToken,
      ) ??
      Future.value();

  Completer<void>? _updateCompleter;
  Timer? _periodicTimer;

  /// What the connection banner says. Uploads pause while it says the
  /// connection is lost, and run once when it returns.
  final ValueListenable<ConnectionStatus> _connectionStatus;
  late ConnectionStatus _lastConnectionStatus;

  void start() {
    // Backstop pin (the authoritative pin is at the loggedIn observation in
    // _initDatabase): covers any path where that didn't run before start.
    pinAccountId();
    // Piggyback app-lifecycle hooks for the dosage engagement tracker; the
    // 5-minute tick below is its heartbeat flush. Idempotent re-registration
    // so a restart can't stack observers.
    WidgetsBinding.instance
      ..removeObserver(this)
      ..addObserver(this);
    _lastConnectionStatus = _connectionStatus.value;
    _connectionStatus
      ..removeListener(_onConnectionStatusChanged)
      ..addListener(_onConnectionStatusChanged);
    // Open the audio coverage period HERE, not at the first playback: a build
    // that instrumented listening and heard none has to say it was watching, or
    // its zero cannot be told apart from an unknown.
    _audioBuffer?.start();
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      // Heartbeat flush of any open engagement span (no-op when none / dark).
      unawaited(_tracker?.flushOpenSpan() ?? Future.value());
      // Heartbeat flush of buffered audio signals + this period's coverage
      // declarations (no-op when dark). Fire-and-forget: nothing waits on it.
      unawaited(_flushAudio());
      if (!dataService.isLogged) {
        ErrorHandler.logError(
          e: "User not logged in on periodic analytics update",
          data: {},
        );
        _periodicTimer?.cancel();
        return;
      }
      // Skip if user hasn't set their L2 yet (e.g., mid-onboarding)
      if (_l2 == null) return;
      sendLocalAnalyticsToAnalyticsRoom();
    });
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    _connectionStatus.removeListener(_onConnectionStatusChanged);
    _periodicTimer?.cancel();
    // Await the final flush so the last open engagement span is actually sent —
    // callers dispose BEFORE invalidating the bearer, so the POST uses a valid
    // token. Dispose the account's tracker via the registry (isolated to this
    // account); a test-injected tracker is flushed directly.
    final injected = _injectedTracker;
    if (injected != null) {
      await injected.flushOpenSpan();
    } else {
      await DosageEngagementTracker.disposeAccount(_accountUserId);
    }
    // Same rule for the audio lane: drain EVERYTHING under the still-valid
    // bearer. A listening observation has no Matrix artefact to re-derive it
    // from, so this is its last chance.
    final injectedBuffer = _injectedAudioBuffer;
    if (injectedBuffer != null) {
      await injectedBuffer.flush(
        drainAll: true,
        accessToken: dataService.accountAccessToken,
      );
    } else {
      await DosageAudioBuffer.disposeAccount(
        _accountUserId,
        accessToken: dataService.accountAccessToken,
      );
    }
    // Drop this account's exposure buffer. Anything still in it is discarded:
    // the store this would drain into is deleted moments from now, and the
    // pre-logout save has already had its chance at it.
    ListeningExposureBuffer.disposeAccount(_accountUserId);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A span represents FOREGROUND engagement, so any move off `resumed`
    // (inactive/paused/detached/hidden) closes and flushes it; it reopens on
    // the next learner activity.
    if (state != AppLifecycleState.resumed) {
      unawaited(_tracker?.flushOpenSpan() ?? Future.value());
      // Backgrounding is where a session most often ends without a teardown, so
      // it is the audio lane's best chance to land the period it just observed.
      unawaited(_flushAudio());
      // Same reasoning for exposure, one step short: draining moves the open
      // window into the DURABLE local store, which survives an app kill and
      // goes out on the next flush. Nothing is sent from here.
      final lang = _l2OrNull;
      if (lang != null) unawaited(_drainListeningExposure(lang));
    }
  }

  /// Sends what built up while the connection was lost, as soon as it returns.
  void _onConnectionStatusChanged() {
    final wasLost = _lastConnectionStatus.isLost;
    _lastConnectionStatus = _connectionStatus.value;
    if (!wasLost || _lastConnectionStatus.isLost) return;
    final lang = _l2OrNull;
    if (lang == null || !dataService.isLogged) return;
    unawaited(_flushAfterInFlightUpload(lang));
  }

  /// An upload already in flight may have started before the connection was
  /// lost and still fail, so the reconnect flush runs after it rather than
  /// joining it.
  Future<void> _flushAfterInFlightUpload(LanguageModel lang) async {
    await _updateCompleter?.future;
    await sendLocalAnalyticsToAnalyticsRoom(l2Override: lang);
  }

  LanguageModel? get _l2 => MatrixState.pangeaController.userController.userL2;

  /// The account's L2, or null when app state is not up yet.
  ///
  /// `MatrixState.pangeaController` is a `late static`, so reading it THROWS
  /// rather than returning null before the app has initialized it. Every other
  /// reader here runs behind the heartbeat, which only ticks once the app is
  /// up; [didChangeAppLifecycleState] does not — the framework calls it on the
  /// UI thread, and a throw there would stall backgrounding. So that one path
  /// asks for the language in a form that can answer "not yet".
  LanguageModel? get _l2OrNull {
    try {
      return _l2;
    } catch (_) {
      return null;
    }
  }

  Future<Room?> _getAnalyticsRoom({LanguageModel? l2Override}) async {
    final l2 = l2Override ?? _l2;
    if (l2 == null) return null;

    final analyticsRoom = await dataService.getAnalyticsRoom(l2);
    return analyticsRoom;
  }

  Future<void> onUpdateLanguages(LanguageUpdate update) async {
    await sendLocalAnalyticsToAnalyticsRoom(l2Override: update.prevTargetLang);
    await dataService.reinitialize();

    final data = await dataService.derivedData(update.targetLang.langCodeShort);
    MatrixState.pangeaController.userController.updateAnalyticsProfile(
      languageCode: update.targetLang.langCodeShort,
      level: data.level,
    );
  }

  Future<void> addAnalytics(
    String? targetID,
    List<OneConstructUse> newConstructs,
    String language, {
    bool forceUpdate = false,
  }) async {
    await dataService.updateDispatcher.sendLocalAnalyticsUpdate(
      AnalyticsUpdate(newConstructs, targetID: targetID),
      language,
    );

    final localConstructCount = await dataService.getLocalConstructCount(
      language,
    );
    final lastUpdated = await dataService.getLastUpdatedAnalytics(language);
    final difference = DateTime.now().difference(lastUpdated ?? DateTime.now());

    if (forceUpdate ||
        localConstructCount > _maxMessagesCached ||
        difference.inMinutes > 10) {
      sendLocalAnalyticsToAnalyticsRoom();
    }
  }

  /// Moves any buffered listening exposure into the local store.
  ///
  /// Deliberately called from [sendLocalAnalyticsToAnalyticsRoom] rather than
  /// wired separately: every path that flushes analytics already goes through
  /// there — the heartbeat, the [addAnalytics] triggers, a language switch and,
  /// the one that matters most, the pre-logout save in `p_logout`, which is the
  /// last moment a valid bearer exists before the store is deleted.
  Future<void> _drainListeningExposure(LanguageModel language) async {
    final buffer = ListeningExposureBuffer.forAccount(_accountUserId);
    if (buffer == null || buffer.isEmpty) return;
    // Only this language's rows. The buffer may be holding exposure in others —
    // a voice message in a language that is not the L2, a word tapped in a
    // message somebody wrote in their own language — and filing those here is
    // exactly the mislabeling per-language isolation forbids. They stay held,
    // and are evicted by the buffer's own bound if no drain ever claims them.
    final uses = buffer.drain(language.langCodeShort);
    if (uses.isEmpty) return;
    try {
      // No targetID: a drain is not a message, and the local store keys on its
      // own stamp anyway. One drain is one write batch, which is what keeps
      // exposure from moving the `_maxMessagesCached` flush trigger.
      await addAnalytics(null, uses, language.langCodeShort);
    } catch (err, s) {
      // The drain already emptied the buffer, so a failed write would lose the
      // window outright. Put it back and let the next drain retry.
      //
      // Caught HERE rather than left to the caller: the lifecycle path calls
      // this through `unawaited`, where a throw is an unhandled async error,
      // and the send path calls it before its own try block. Neither would
      // have restored the rows.
      buffer.restore(language.langCodeShort, uses);
      ErrorHandler.logErrorOnce(
        key: "listening-exposure-drain-failed",
        e: err,
        s: s,
        data: {"rows": uses.length},
        level: SentryLevel.warning,
      );
    }
  }

  Future<void> sendLocalAnalyticsToAnalyticsRoom({
    LanguageModel? l2Override,
  }) async {
    final lang = l2Override ?? _l2;
    if (lang == null) {
      ErrorHandler.logError(
        e: "No L2 language set for user",
        data: {"l2Override": l2Override},
        level: SentryLevel.warning,
      );
      return;
    }

    // Before the in-flight check, not after: a logout-time save that coincided
    // with a heartbeat would otherwise return early and leave the window's
    // exposure in a buffer that is about to be dropped.
    await _drainListeningExposure(lang);

    // A send now would fail after the SDK's full send timeout. The uses stay
    // on the device, and the reconnect flush sends them.
    if (_connectionStatus.value.isLost) return;

    final inProgress =
        _updateCompleter != null && !_updateCompleter!.isCompleted;

    if (inProgress) {
      await _updateCompleter!.future;
      return;
    }

    _updateCompleter = Completer<void>();
    try {
      await _updateAnalytics(lang);
    } on AnalyticsDatabaseClosedException catch (err, s) {
      // The store is gone and this instance cannot revive it, so every later
      // tick would fail identically. Stop the timer rather than let a dead
      // database generate one Sentry event every 5 minutes for the life of
      // the session (#8525) — that loop is what made this look like hundreds
      // of incidents instead of one.
      _periodicTimer?.cancel();
      _periodicTimer = null;
      // Transient by nature: teardown racing an in-flight flush. Reported
      // once per session, at warning, per the severity policy in
      // repos-and-error-handling.instructions.md.
      ErrorHandler.logErrorOnce(
        key: "analytics-update-database-closed",
        e: err,
        s: s,
        data: {"l2Override": l2Override},
        level: SentryLevel.warning,
      );
    } catch (err, s) {
      ErrorHandler.logError(e: err, s: s, data: {"l2Override": l2Override});
    } finally {
      _updateCompleter?.complete();
      _updateCompleter = null;
    }
  }

  /// Uploads the pending local batches and clears what the server accepted.
  /// Uses recorded while the upload was in flight land in new batches with new
  /// keys and stay pending for the next flush (#7720), and so does whatever
  /// the server did not accept (#9511).
  Future<void> _updateAnalytics(LanguageModel language) async {
    final batches = (await dataService.getLocalUseBatches(
      language.langCodeShort,
    )).entries.toList();
    if (batches.isEmpty) return;
    final analyticsRoom = await _getAnalyticsRoom(l2Override: language);
    if (analyticsRoom == null) {
      debugPrint(
        "No analytics room found for L2 Override: ${language.langCodeShort}",
      );
      return;
    }

    final arrivals = ServerEventArrivals(analyticsRoom);
    try {
      final upload = await analyticsRoom.sendConstructsEvent(
        batches.map((batch) => batch.value).toList(),
      );
      if (!upload.allAccepted) _reportRefusedUpload(upload);
      await _waitForServerCopy(arrivals, upload);
      await _clearAcceptedUses(language, batches, upload);
    } finally {
      await arrivals.cancel();
    }
  }

  /// Clears the batches the server accepted, and cuts a batch it accepted
  /// only the first part of down to the uses it did not, so that part is not
  /// sent twice.
  Future<void> _clearAcceptedUses(
    LanguageModel language,
    List<MapEntry<String, List<OneConstructUse>>> batches,
    ConstructsUploadResult upload,
  ) async {
    final acceptedKeys = batches
        .take(upload.acceptedBatchCount)
        .map((batch) => batch.key)
        .toList();
    final trimmedBatches = <String, List<OneConstructUse>>{};
    if (upload.partlyAcceptedUseCount > 0) {
      final splitBatch = batches[upload.acceptedBatchCount];
      trimmedBatches[splitBatch.key] = splitBatch.value.sublist(
        upload.partlyAcceptedUseCount,
      );
    }
    if (acceptedKeys.isEmpty && trimmedBatches.isEmpty) return;
    await dataService.clearLocalAnalytics(
      language.langCodeShort,
      acceptedKeys,
      trimmedBatches: trimmedBatches,
    );
  }

  void _reportRefusedUpload(ConstructsUploadResult upload) {
    // Expected when the connection dropped during the upload; the banner has
    // usually caught up by the time the SDK gives up on the send.
    if (_connectionStatus.value.isLost) return;
    ErrorHandler.logErrorOnce(
      key: "analytics-upload-refused",
      e: "The server did not accept an analytics upload",
      data: {
        "batchCount": upload.batchCount,
        "acceptedBatchCount": upload.acceptedBatchCount,
      },
      level: SentryLevel.warning,
    );
  }

  /// Waits for the server's copy of the last accepted event to reach the
  /// device. Clearing the batches before it arrives leaves their uses out of
  /// the XP total until it does.
  Future<void> _waitForServerCopy(
    ServerEventArrivals arrivals,
    ConstructsUploadResult upload,
  ) async {
    final lastEventId = upload.acceptedEventIds.lastOrNull;
    if (lastEventId == null) return;
    final arrived = await arrivals.waitFor(lastEventId, _serverCopyTimeout);
    if (arrived) return;
    // The server has the uses, so clearing is still right: holding the batches
    // would send them a second time.
    ErrorHandler.logErrorOnce(
      key: "analytics-upload-server-copy-late",
      e: "The server's copy of an analytics upload did not arrive in time",
      data: {"timeoutSeconds": _serverCopyTimeout.inSeconds},
      level: SentryLevel.warning,
    );
  }

  Future<void> sendActivityAnalytics(String roomId, LanguageModel lang) async {
    final analyticsRoom = await _getAnalyticsRoom(l2Override: lang);
    if (analyticsRoom == null) return;

    await analyticsRoom.addActivityRoomIds({roomId});
  }

  Future<void> blockConstructs(List<ConstructIdentifier> constructIds) async {
    final analyticsRoom = await _getAnalyticsRoom();
    if (analyticsRoom == null) return;

    final current = analyticsRoom.analyticsSettings;
    final blockedConstructs = current.blockedConstructs;
    final updated = current.copyWith(
      blockedConstructs: {...blockedConstructs, ...constructIds},
    );

    await analyticsRoom.setAnalyticsSettings(updated);
  }

  Future<void> unblockConstructs(List<ConstructIdentifier> constructIds) async {
    final analyticsRoom = await _getAnalyticsRoom();
    if (analyticsRoom == null) return;

    final current = analyticsRoom.analyticsSettings;
    final remaining = current.blockedConstructs
        .where((c) => !constructIds.contains(c))
        .toSet();
    if (remaining.length == current.blockedConstructs.length) return;

    await analyticsRoom.setAnalyticsSettings(
      current.copyWith(blockedConstructs: remaining),
    );
  }

  Future<void> setLemmaInfo(
    ConstructIdentifier constructId, {
    String? emoji,
    String? meaning,
  }) async {
    final analyticsRoom = await _getAnalyticsRoom();
    if (analyticsRoom == null) return;

    final userLemmaInfo = analyticsRoom.getUserSetLemmaInfo(constructId);
    final updated = userLemmaInfo.copyWith(
      emojis: emoji == null ? null : [emoji],
      meaning: meaning,
    );
    if (userLemmaInfo == updated) return;

    try {
      await analyticsRoom.setUserSetLemmaInfo(constructId, updated);
    } catch (err, s) {
      debugger(when: kDebugMode);
      ErrorHandler.logError(e: err, data: userLemmaInfo.toJson(), s: s);
    }
  }
}
