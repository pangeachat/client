import 'dart:convert';

import 'package:async/async.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart';

import 'package:fluffychat/features/subscription/models/subscription_details.dart';
import 'package:fluffychat/features/subscription/repo/subscription_repo.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class AllProductsCacheEntry {
  final List<SubscriptionDetails> allProducts;
  final DateTime timestamp;

  const AllProductsCacheEntry({
    required this.allProducts,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    "all_products": allProducts.map((p) => p.toJson()).toList(),
    "timestamp": timestamp.millisecondsSinceEpoch,
  };

  factory AllProductsCacheEntry.fromJson(Map<String, dynamic> json) =>
      AllProductsCacheEntry(
        allProducts: List.from(json["all_products"])
            .map(
              (e) => SubscriptionDetails.fromJson(Map<String, dynamic>.from(e)),
            )
            .toList(),
        timestamp: DateTime.fromMillisecondsSinceEpoch(json["timestamp"]),
      );

  static const Duration _cacheDuration = Duration(hours: 24);

  bool get isExpired =>
      timestamp.isBefore(DateTime.now().subtract(_cacheDuration));
}

class AllProductsRepo {
  static final GetStorage _storage = GetStorage("all_products_storage");

  static Future<Result<List<SubscriptionDetails>>>? _inflightRequest;

  static Future<Result<List<SubscriptionDetails>>> get() async {
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
    final allProducts = response.result;
    if (allProducts != null) {
      await _setCached(allProducts);
    }

    _inflightRequest = null;
    return response;
  }

  static Future<Result<List<SubscriptionDetails>>> _fetch() async {
    try {
      final Requests req = Requests(
        choreoApiKey: Environment.choreoApiKey,
        accessToken: MatrixState.pangeaController.userController.accessToken,
      );
      final Response res = await req.get(url: PApiUrls.rcProductsChoreo);

      if (res.statusCode >= 400) {
        throw res;
      }

      final Map<String, dynamic> json = jsonDecode(res.body);
      final RCProductsResponseModel resp = RCProductsResponseModel.fromJson(
        json,
      );
      final allProducts = resp.allProducts;
      return Result.value(allProducts);
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {});
      return Result.error(e);
    }
  }

  static Future<List<SubscriptionDetails>?> _getCached() async {
    await GetStorage.init("all_products_storage");
    final entry = _storage.read("all_products");
    if (entry == null) return null;
    try {
      final parsed = AllProductsCacheEntry.fromJson(entry);
      if (parsed.isExpired) {
        await _storage.remove("all_products");
        return null;
      }
      return parsed.allProducts;
    } catch (_) {
      await _storage.remove("all_products");
      return null;
    }
  }

  static Future<void> _setCached(List<SubscriptionDetails> response) async {
    await GetStorage.init("all_products_storage");
    final entry = AllProductsCacheEntry(
      allProducts: response,
      timestamp: DateTime.now(),
    );
    await _storage.write("all_products", entry.toJson());
  }
}
