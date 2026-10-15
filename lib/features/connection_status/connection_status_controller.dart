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

  int _consecutiveFailures = 0;
  bool _deviceReportsNoNetwork = false;
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

  /// Whether the app is in the foreground. A suspended app's requests fail
  /// because the OS paused them, not because the connection is gone. The
  /// filter check reads it too, so the two agree. Replaced in tests.
  bool Function() isAppResumed = _isAppResumed;

  /// Takes one update from the active account's sync loop.
  void onSyncStatus(SyncStatusUpdate update) {
    // A sync loop is running, so the device's own network reports now mean
    // something to the banner.
    _networkChanges ??= onNetworkChanged().listen(_onNetworkChanged);
    switch (update.status) {
      case SyncStatus.finished:
        _consecutiveFailures = 0;
        _onConnected();
      case SyncStatus.error:
        // A Matrix error is the server answering; a failure while processing
        // the answer is ours. Only a request that got no usable answer is a
        // lost connection.
        if (update.error?.exception is! SyncConnectionException) return;
        if (!isAppResumed()) return;
        _consecutiveFailures++;
        if (_consecutiveFailures >= failuresBeforeLost) _onLost();
      case SyncStatus.waitingForResponse:
      case SyncStatus.processing:
      case SyncStatus.cleaningUp:
        break;
    }
  }

  void _onNetworkChanged(List<ConnectivityResult> results) {
    _deviceReportsNoNetwork =
        results.isNotEmpty &&
        results.every((result) => result == ConnectivityResult.none);
    if (_deviceReportsNoNetwork) {
      _setLost(ConnectionStatus.offline);
      return;
    }
    // A new network may answer where the last one did not; the next sync
    // says whether the chat server does.
    if (status.value.isLost) {
      _classifiedAt = null;
      _onLost();
    }
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

  /// Forgets the connection state, for an account that signed out: its sync
  /// loop has stopped, so nothing would clear a lost connection.
  void reset() {
    _consecutiveFailures = 0;
    _deviceReportsNoNetwork = false;
    _classifiedAt = null;
    _backOnlineTimer?.cancel();
    _backOnlineTimer = null;
    unawaited(_networkChanges?.cancel());
    _networkChanges = null;
    status.value = ConnectionStatus.connected;
  }

  static bool _isAppResumed() {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  @visibleForTesting
  void resetForTest() {
    reset();
    _classifying = null;
    probe = NetworkProbe.probe;
    onNetworkChanged = () => Connectivity().onConnectivityChanged;
    currentNetworkType = NetworkType.current;
    isAppResumed = _isAppResumed;
  }
}

class _ChatServerUnreachableException implements Exception {
  @override
  String toString() =>
      'ChatServerUnreachableException: the device is online but the chat '
      'server is not answering';
}
