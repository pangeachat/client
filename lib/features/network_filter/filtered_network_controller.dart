import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/network_filter/network_help_repo.dart';
import 'package:fluffychat/features/network_filter/network_host_category.dart';
import 'package:fluffychat/features/network_filter/network_probe.dart';
import 'package:fluffychat/features/network_filter/network_type.dart';
import 'package:fluffychat/features/network_filter/network_verdict.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';

/// Which host categories the current network blocks, and the checks that
/// decide it. See filtered-network.instructions.md.
///
/// A check runs only after something failed — a request with no response, a
/// video opening, a sign-in starting — so a healthy network never pays for
/// one. A category stays [blocked] until a request to its host succeeds or a
/// check after a network change finds it reachable.
class FilteredNetworkController {
  FilteredNetworkController._();

  static final FilteredNetworkController instance =
      FilteredNetworkController._();

  /// How long one check's answer stands before another failure re-checks.
  static const Duration recheckAfter = Duration(seconds: 30);

  /// The categories the current network blocks.
  final ValueNotifier<Set<NetworkHostCategory>> blocked = ValueNotifier(
    const {},
  );

  final Map<NetworkHostCategory, DateTime> _firstBlockedAt = {};
  final Map<NetworkHostCategory, DateTime> _lastCheckedAt = {};
  final Map<NetworkHostCategory, Future<NetworkVerdict>> _inFlight = {};
  StreamSubscription<List<ConnectivityResult>>? _networkChanges;

  @visibleForTesting
  Future<NetworkProbeResult> Function(Uri url) probe = NetworkProbe.probe;

  @visibleForTesting
  Stream<List<ConnectivityResult>> Function() onNetworkChanged = () =>
      Connectivity().onConnectivityChanged;

  @visibleForTesting
  Future<NetworkType> Function() currentNetworkType = NetworkType.current;

  /// The platform as a Sentry tag and in a help request.
  static String get platformName => kIsWeb ? 'web' : defaultTargetPlatform.name;

  /// When the earliest of the [blocked] categories was first seen blocked
  /// this session, or null when none is blocked.
  DateTime? get firstBlockedAt => blocked.value
      .map((category) => _firstBlockedAt[category])
      .nonNulls
      .fold<DateTime?>(
        null,
        (earliest, at) =>
            earliest == null || at.isBefore(earliest) ? at : earliest,
      );

  /// Checks [category] now, sharing a check already in flight.
  Future<NetworkVerdict> check(NetworkHostCategory category) =>
      _inFlight[category] ??= _check(category).whenComplete(() {
        // A block body, not an arrow: `remove` returns this very future, and
        // whenComplete would wait on it — the check would wait on itself.
        _inFlight.remove(category);
      });

  /// Checks [category] unless a check answered within [recheckAfter], so a
  /// burst of failures costs one check.
  Future<void> checkIfStale(NetworkHostCategory category) async {
    final lastChecked = _lastCheckedAt[category];
    if (lastChecked != null &&
        DateTime.now().difference(lastChecked) < recheckAfter) {
      return;
    }
    await check(category);
  }

  /// Runs [request] to [url], noting whether it reached a server. A
  /// [http.ClientException] is a request that got no response at all.
  Future<T> observe<T>(Uri url, Future<T> request) async {
    final T response;
    try {
      response = await request;
    } on http.ClientException {
      _note(() => onRequestFailed(url));
      rethrow;
    }
    _note(() => onRequestSucceeded(url));
    return response;
  }

  /// Runs [noting] so that a failure in the bookkeeping is reported, once,
  /// and never fails the request being observed.
  void _note(void Function() noting) {
    try {
      noting();
    } catch (e, s) {
      ErrorHandler.logErrorOnce(
        key: 'filtered-network-observe',
        e: e,
        s: s,
        data: {},
      );
    }
  }

  void onRequestFailed(Uri url) {
    final category = NetworkHostCategory.ofRequest(url);
    if (category != null) unawaited(checkIfStale(category));
  }

  void onRequestSucceeded(Uri url) {
    // Every request lands here; on a healthy network there is nothing to do.
    if (blocked.value.isEmpty && !NetworkHelpRepo.isWaiting) return;
    final category = NetworkHostCategory.ofRequest(url);
    if (category == null) return;
    _clear(category);
    if (category == NetworkHostCategory.pangeaApi) {
      unawaited(NetworkHelpRepo.flush());
    }
  }

  Future<NetworkVerdict> _check(NetworkHostCategory category) async {
    final needed = await probe(category.probeUrl);
    // The neutral addresses matter only when the host failed: they tell a
    // filter from a dead connection.
    final neutralAnswered =
        needed.blocked &&
        (await Future.wait(
          NetworkProbe.neutralUrls.map(probe),
        )).contains(NetworkProbeResult.answered);
    final verdict = NetworkVerdict.of(
      needed: needed,
      neutralAnswered: neutralAnswered,
    );
    _lastCheckedAt[category] = DateTime.now();
    switch (verdict) {
      case NetworkVerdict.filtered:
        _markBlocked(category, needed);
      case NetworkVerdict.reachable:
        _clear(category);
      case NetworkVerdict.offline:
        // Offline says nothing about a filter, so a block already seen stands.
        break;
    }
    return verdict;
  }

  void _markBlocked(NetworkHostCategory category, NetworkProbeResult needed) {
    if (blocked.value.contains(category)) return;
    _firstBlockedAt[category] ??= DateTime.now();
    blocked.value = {...blocked.value, category};
    _networkChanges ??= onNetworkChanged().listen((_) => _recheckBlocked());
    unawaited(_report(category, needed));
  }

  void _clear(NetworkHostCategory category) {
    if (!blocked.value.contains(category)) return;
    blocked.value = {...blocked.value}..remove(category);
    if (blocked.value.isNotEmpty) return;
    unawaited(_networkChanges?.cancel());
    _networkChanges = null;
  }

  /// A new network may let through what the last one blocked, and may be the
  /// good connection a waiting help request needs.
  void _recheckBlocked() {
    for (final category in blocked.value) {
      unawaited(check(category));
    }
    unawaited(NetworkHelpRepo.flush());
  }

  Future<void> _report(
    NetworkHostCategory category,
    NetworkProbeResult needed,
  ) async {
    final networkType = await currentNetworkType();
    await ErrorHandler.logErrorOnce(
      key: 'filtered-network-${category.name}',
      e: _FilteredNetworkException(category),
      level: SentryLevel.error,
      data: {'category': category.name, 'probeResult': needed.name},
      tags: {
        'blocked_host_category': category.name,
        'app_platform': platformName,
        'network_type': networkType.name,
      },
    );
  }

  @visibleForTesting
  void resetForTest() {
    blocked.value = const {};
    _firstBlockedAt.clear();
    _lastCheckedAt.clear();
    _inFlight.clear();
    unawaited(_networkChanges?.cancel());
    _networkChanges = null;
    probe = NetworkProbe.probe;
    onNetworkChanged = () => Connectivity().onConnectivityChanged;
    currentNetworkType = NetworkType.current;
  }
}

class _FilteredNetworkException implements Exception {
  final NetworkHostCategory category;

  _FilteredNetworkException(this.category);

  @override
  String toString() =>
      'FilteredNetworkException: this network blocks ${category.name}';
}
