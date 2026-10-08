import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:http/http.dart' show ClientException;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/network_filter/network_help_request.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';

enum NetworkHelpStatus {
  /// Nothing sent today, nothing waiting.
  none,

  /// Saved on the device until the CMS can be reached.
  waiting,

  /// Sent today. The app sends at most one a day from each device.
  sent,

  /// The CMS refused it. The request stays saved, and the next session tries
  /// once more.
  refused,
}

/// Sends a [NetworkHelpRequest] to the CMS, which emails it to the team. A
/// request that cannot reach the CMS waits on the device and goes out on the
/// next good connection: when a Pangea API request next succeeds, or the
/// device changes network. See filtered-network.instructions.md, "Asking
/// Pangea for help".
abstract final class NetworkHelpRepo {
  static const String _waitingKey = 'filtered_network_help_request';
  static const String _lastSentDayKey = 'filtered_network_help_last_sent_day';

  static final ValueNotifier<NetworkHelpStatus> status = ValueNotifier(
    NetworkHelpStatus.none,
  );

  static bool _sending = false;

  /// Whether a request waits on the device. Held in memory so the flush after
  /// every successful API call costs nothing when nothing waits; [initialize]
  /// reads it from the device once at startup.
  static bool _waiting = false;

  static bool get isWaiting => _waiting;

  static String get _today => DateTime.now().toIso8601String().substring(0, 10);

  /// Reads the stored state, then sends a request left waiting by an earlier
  /// session: app start is often the next good connection.
  static Future<void> initialize() async {
    await refreshStatus();
    await flush();
  }

  /// Reads the stored state into [status]. A refusal stands for the session.
  static Future<void> refreshStatus() async {
    if (status.value == NetworkHelpStatus.refused) return;
    final prefs = await SharedPreferences.getInstance();
    _waiting = prefs.containsKey(_waitingKey);
    status.value = _waiting
        ? NetworkHelpStatus.waiting
        : prefs.getString(_lastSentDayKey) == _today
        ? NetworkHelpStatus.sent
        : NetworkHelpStatus.none;
  }

  /// Saves [request] and tries to send it. Does nothing when a request is
  /// already waiting or one was sent today.
  static Future<void> submit(NetworkHelpRequest request) async {
    await refreshStatus();
    if (status.value != NetworkHelpStatus.none) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_waitingKey, jsonEncode(request.toJson()));
    _waiting = true;
    status.value = NetworkHelpStatus.waiting;
    await flush();
  }

  /// Sends the waiting request, if there is one.
  static Future<void> flush() async {
    // A refused request is not resent after every successful API call for
    // the rest of the session.
    if (!_waiting || _sending || status.value == NetworkHelpStatus.refused) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_waitingKey);
    if (stored == null) return;
    _sending = true;
    final request = NetworkHelpRequest.fromJson(
      jsonDecode(stored) as Map<String, dynamic>,
    );
    try {
      await Requests().post(
        url: PApiUrls.cmsFormSubmissions,
        body: request.toFormSubmission(),
        enrichBody: false,
      );
      await prefs.remove(_waitingKey);
      _waiting = false;
      await prefs.setString(_lastSentDayKey, _today);
      status.value = NetworkHelpStatus.sent;
    } on ClientException {
      // silent-ok: no response is the case this queue exists for; the request
      // waits for the next good connection.
    } catch (e, s) {
      status.value = NetworkHelpStatus.refused;
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'blockedCategories': request.toJson()['blockedCategories']},
      );
    } finally {
      _sending = false;
    }
  }

  @visibleForTesting
  static void resetForTest() {
    status.value = NetworkHelpStatus.none;
    _sending = false;
    _waiting = false;
  }
}
