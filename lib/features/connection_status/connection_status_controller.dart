import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/connection_status/filtered_network_controller.dart';
import 'package:fluffychat/features/connection_status/network_probe.dart';
import 'package:fluffychat/features/connection_status/network_type.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';

/// What the connection banner says. See connection-status.instructions.md,
/// "Losing the connection".
enum ConnectionStatus {
  connected,

  /// The device has no connection at all.
  offline,

  /// The device is online, but the chat server is not answering or is
  /// returning errors.
  unreachable,

  /// The connection just came back; shown for [ConnectionStatusController.backOnlineFor].
  backOnline;

  bool get isLost => this == offline || this == unreachable;
}

/// Whether the app's connection to the chat server is lost, and why.
///
/// The chat server sync is the signal: it runs the whole time the app is
/// open and retries every few seconds. The connection counts as lost after
/// [failuresBeforeLost] failed attempts in a row, or at once when the device
/// reports no network. A filtered chat server is [FilteredNetworkController]'s
/// to decide; the observer client already starts that check on every failed
/// sync request.
class ConnectionStatusController {
  ConnectionStatusController._();

  static final ConnectionStatusController instance =
      ConnectionStatusController._();

  /// A single failure is ignored, because flaky connections drop one now and
  /// then.
  static const int failuresBeforeLost = 2;

  /// How long "Back online" shows before the banner goes away.
  static const Duration backOnlineFor = Duration(seconds: 3);

  /// How long one answer to "is the device online?" stands while the
  /// connection stays lost.
  static const Duration reclassifyAfter = Duration(seconds: 30);

  final ValueNotifier<ConnectionStatus> status = ValueNotifier(
    ConnectionStatus.connected,
  );

  /// Whether the app cannot reach Pangea now: the connection is lost, or this
  /// network blocks the chat server or the Pangea API. Either way a banner is
  /// up, and practice started now runs offline. See
  /// practice-exercises.instructions.md, "Offline Practice".
  bool get cannotReachPangea =>
      status.value.isLost ||
      FilteredNetworkController.instance.blocked.value.any((c) => c.stopsApp);

  /// Notifies when [cannotReachPangea] may have changed.
  late final Listenable reachability = Listenable.merge([
    status,
    FilteredNetworkController.instance.blocked,
  ]);

  int _consecutiveFailures = 0;
  bool _deviceReportsNoNetwork = false;

  /// Whether an account's sync loop is reporting in. Before sign-in none is,
  /// so the device's own report is the only signal, and it also says when the
  /// connection is back. See connection-status.instructions.md, "Before
  /// sign-in".
  bool _syncReporting = false;
  DateTime? _classifiedAt;
  Future<void>? _classifying;
  Timer? _backOnlineTimer;
  StreamSubscription<List<ConnectivityResult>>? _networkChanges;

  @visibleForTesting
  Future<NetworkProbeResult> Function(Uri url) probe = NetworkProbe.probe;

  @visibleForTesting
  Stream<List<ConnectivityResult>> Function() onNetworkChanged = () =>
      Connectivity().onConnectivityChanged;

  @visibleForTesting
  Future<NetworkType> Function() currentNetworkType = NetworkType.current;

  /// Whether the app is in the foreground: on screen, focused or not. A
  /// hidden app's requests fail because the OS paused them, not because the
  /// connection is gone; an unfocused window's requests run on. The filter
  /// check reads it too, so the two agree. Replaced in tests. See
  /// connection-status.instructions.md, "Telling the causes apart".
  bool Function() isAppInForeground = _isAppInForeground;

  /// Takes one update from the active account's sync loop.
  void onSyncStatus(SyncStatusUpdate update) {
    _syncReporting = true;
    watchDevice();
    switch (update.status) {
      case SyncStatus.finished:
        _consecutiveFailures = 0;
        _onConnected();
      case SyncStatus.error:
        // A Matrix error is the server answering; a failure while processing
        // the answer is ours. Only a request that got no usable answer is a
        // lost connection.
        if (update.error?.exception is! SyncConnectionException) return;
        if (!isAppInForeground()) return;
        _consecutiveFailures++;
        if (_consecutiveFailures >= failuresBeforeLost) _onLost();
      case SyncStatus.waitingForResponse:
      case SyncStatus.processing:
      case SyncStatus.cleaningUp:
        break;
    }
  }

  /// Watches the device's own network report. The banner calls this when it
  /// comes on screen, so the report counts before an account signs in. See
  /// connection-status.instructions.md, "Before sign-in".
  void watchDevice() {
    _networkChanges ??= onNetworkChanged().listen(_onNetworkChanged);
  }

  void _onNetworkChanged(List<ConnectivityResult> results) {
    _deviceReportsNoNetwork =
        results.isNotEmpty &&
        results.every((result) => result == ConnectivityResult.none);
    if (_deviceReportsNoNetwork) {
      _setLost(ConnectionStatus.offline);
      return;
    }
    if (!status.value.isLost) return;
    // Before sign-in no sync can confirm the connection is back, so the
    // device's report decides.
    if (!_syncReporting) {
      _onConnected();
      return;
    }
    // A new network may answer where the last one did not; the next sync
    // says whether the chat server does.
    _classifiedAt = null;
    _onLost();
  }

  void _onLost() {
    if (_deviceReportsNoNetwork) {
      _setLost(ConnectionStatus.offline);
      return;
    }
    final classifiedAt = _classifiedAt;
    if (status.value.isLost &&
        classifiedAt != null &&
        DateTime.now().difference(classifiedAt) < reclassifyAfter) {
      return;
    }
    _classifying ??= _classify().whenComplete(() => _classifying = null);
  }

  /// Asks the neutral addresses whether the device is online at all.
  Future<void> _classify() async {
    final results = await Future.wait(NetworkProbe.neutralUrls.map(probe));
    final deviceOnline = results.contains(NetworkProbeResult.answered);
    // A sync may have succeeded, or the device lost its network, while the
    // probes ran.
    if (_consecutiveFailures < failuresBeforeLost || _deviceReportsNoNetwork) {
      return;
    }
    _classifiedAt = DateTime.now();
    _setLost(
      deviceOnline ? ConnectionStatus.unreachable : ConnectionStatus.offline,
    );
    if (deviceOnline) unawaited(_reportUnreachable());
  }

  void _setLost(ConnectionStatus lost) {
    _backOnlineTimer?.cancel();
    _backOnlineTimer = null;
    status.value = lost;
  }

  void _onConnected() {
    _classifiedAt = null;
    if (!status.value.isLost) return;
    status.value = ConnectionStatus.backOnline;
    _backOnlineTimer?.cancel();
    _backOnlineTimer = Timer(backOnlineFor, () {
      _backOnlineTimer = null;
      if (status.value == ConnectionStatus.backOnline) {
        status.value = ConnectionStatus.connected;
      }
    });
  }

  /// One warning per session: real users' view of an outage, which can catch
  /// a regional or DNS failure our server-side checks miss.
  Future<void> _reportUnreachable() async {
    final networkType = await currentNetworkType();
    await ErrorHandler.logErrorOnce(
      key: 'connection-status-chat-server-unreachable',
      e: _ChatServerUnreachableException(),
      level: SentryLevel.warning,
      data: {'consecutiveFailures': _consecutiveFailures},
      tags: {
        'app_platform': FilteredNetworkController.platformName,
        'network_type': networkType.name,
      },
    );
  }

  /// Forgets an account's connection state when it signs out: its sync loop
  /// has stopped, so nothing would clear a lost connection. The device's own
  /// report outlives the account, for the sign-in page.
  void reset() {
    _consecutiveFailures = 0;
    _syncReporting = false;
    _classifiedAt = null;
    _backOnlineTimer?.cancel();
    _backOnlineTimer = null;
    status.value = _deviceReportsNoNetwork
        ? ConnectionStatus.offline
        : ConnectionStatus.connected;
  }

  static bool _isAppInForeground() =>
      switch (WidgetsBinding.instance.lifecycleState) {
        // Null: the engine has not reported a state yet, so the app has just
        // started. Inactive: a window that lost focus on the web or a
        // computer, or a phone's notification shade or incoming call.
        null || AppLifecycleState.resumed || AppLifecycleState.inactive => true,
        AppLifecycleState.hidden ||
        AppLifecycleState.paused ||
        AppLifecycleState.detached => false,
      };

  @visibleForTesting
  void resetForTest() {
    _deviceReportsNoNetwork = false;
    unawaited(_networkChanges?.cancel());
    _networkChanges = null;
    reset();
    _classifying = null;
    probe = NetworkProbe.probe;
    onNetworkChanged = () => Connectivity().onConnectivityChanged;
    currentNetworkType = NetworkType.current;
    isAppInForeground = _isAppInForeground;
  }
}

class _ChatServerUnreachableException implements Exception {
  @override
  String toString() =>
      'ChatServerUnreachableException: the device is online but the chat '
      'server is not answering';
}
