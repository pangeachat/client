import 'dart:convert';

import 'package:async/async.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart';

import 'package:fluffychat/features/subscription/models/subscription_app_id.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class SubscriptionAppIdsCacheEntry {
  final SubscriptionAppIds appIds;
  final DateTime timestamp;

  const SubscriptionAppIdsCacheEntry({
    required this.appIds,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    "app_ids": appIds.toJson(),
    "timestamp": timestamp.millisecondsSinceEpoch,
  };

  factory SubscriptionAppIdsCacheEntry.fromJson(Map<String, dynamic> json) =>
      SubscriptionAppIdsCacheEntry(
        appIds: SubscriptionAppIds.fromJson(
          Map<String, dynamic>.from(json["app_ids"]),
        ),
        timestamp: DateTime.fromMillisecondsSinceEpoch(json["timestamp"]),
      );

  static const Duration _cacheDuration = Duration(hours: 24);

  bool get isExpired =>
      timestamp.isBefore(DateTime.now().subtract(_cacheDuration));
}

class SubscriptionAppIdsRepo {
  static final GetStorage _storage = GetStorage("subscription_app_ids_storage");

  static Future<Result<SubscriptionAppIds>>? _inflightRequest;

  static Future<Result<SubscriptionAppIds>> get() async {
    final inflight = _inflightRequest;
    if (inflight != null) {
      return inflight;
    }

    final cached = await _getCached();
    if (cached != null) {
      return Result.value(cached);
    }

    final future = _fetch();
    _inflightRequest = future;

    final response = await future;
    final appIds = response.result;
    if (appIds != null) {
      await _setCached(appIds);
    }

    _inflightRequest = null;
    return response;
  }

  static Future<Result<SubscriptionAppIds>> _fetch() async {
    try {
      final Requests req = Requests(
        accessToken: MatrixState.pangeaController.userController.accessToken,
      );
      final Response res = await req.get(url: PApiUrls.rcAppsChoreo);

      if (res.statusCode >= 400) {
        throw res;
      }

      final response = SubscriptionAppIds.fromJson(jsonDecode(res.body));
      return Result.value(response);
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {});
      return Result.error(e);
    }
  }

  static Future<SubscriptionAppIds?> _getCached() async {
    await GetStorage.init("subscription_app_ids_storage");
    final entry = _storage.read("app_ids");
    if (entry == null) return null;
    try {
      final parsed = SubscriptionAppIdsCacheEntry.fromJson(entry);
      if (parsed.isExpired) {
        await _storage.remove("app_ids");
        return null;
      }
      return parsed.appIds;
    } catch (_) {
      await _storage.remove("app_ids");
      return null;
    }
  }

  static Future<void> _setCached(SubscriptionAppIds response) async {
    await GetStorage.init("subscription_app_ids_storage");
    final entry = SubscriptionAppIdsCacheEntry(
      appIds: response,
      timestamp: DateTime.now(),
    );
    await _storage.write("app_ids", entry.toJson());
  }
}
