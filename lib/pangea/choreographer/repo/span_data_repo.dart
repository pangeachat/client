import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:http/http.dart';

import 'package:fluffychat/pangea/choreographer/models/span_data.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import '../../common/constants/model_keys.dart';
import '../../common/network/requests.dart';
import '../../common/network/urls.dart';

class SpanDataRepo {
  static Future<SpanDetailsRepoReqAndRes> getSpanDetails(
    String? accessToken, {
    required SpanDetailsRepoReqAndRes request,
  }) async {
    final Requests req = Requests(
      accessToken: accessToken,
      choreoApiKey: Environment.choreoApiKey,
    );
    final Response res = await req.post(
      url: PApiUrls.spanDetails,
      body: request.toJson(),
    );

    final Map<String, dynamic> json =
        jsonDecode(utf8.decode(res.bodyBytes).toString());

    return SpanDetailsRepoReqAndRes.fromJson(json);
  }
}

class SpanDetailsRepoReqAndRes {
  String userL1;
  String userL2;
  bool enableIT;
  bool enableIGC;
  SpanData span;

  SpanDetailsRepoReqAndRes({
    required this.userL1,
    required this.userL2,
    required this.enableIGC,
    required this.enableIT,
    required this.span,
  });

  Map<String, dynamic> toJson() => {
        ModelKey.userL1: userL1,
        ModelKey.userL2: userL2,
        "enable_it": enableIT,
        "enable_igc": enableIGC,
        'span': span.toJson(),
      };

  factory SpanDetailsRepoReqAndRes.fromJson(Map<String, dynamic> json) =>
      SpanDetailsRepoReqAndRes(
        userL1: json['user_l1'] as String,
        userL2: json['user_l2'] as String,
        enableIT: json['enable_it'] as bool,
        enableIGC: json['enable_igc'] as bool,
        span: SpanData.fromJson(json['span']),
      );

  /// Overrides the equality operator to compare two [SpanDetailsRepoReqAndRes] objects.
  /// Returns true if the objects are identical or have the same property
  /// values (based on the results of the toJson function), false otherwise.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SpanDetailsRepoReqAndRes) return false;
    if (other.userL1 != userL1) return false;
    if (other.userL2 != userL2) return false;
    if (other.enableIT != enableIT) return false;
    if (other.enableIGC != enableIGC) return false;
    if (const ListEquality().equals(
          other.span.choices?.sorted((a, b) => b.value.compareTo(a.value)),
          span.choices?.sorted((a, b) => b.value.compareTo(a.value)),
        ) ==
        false) {
      return false;
    }
    return true;
  }

  /// Overrides the hashCode getter to generate a hash code for the [SpanDetailsRepoReqAndRes] object.
  /// Used as keys in response cache in igc_controller.
  @override
  int get hashCode {
    return Object.hashAll([
      userL1.hashCode,
      userL2.hashCode,
      enableIT.hashCode,
      enableIGC.hashCode,
      if (span.choices != null)
        Object.hashAll(
          span.choices!
              .sorted((a, b) => b.value.compareTo(a.value))
              .map((choice) => choice.hashCode),
        ),
    ]);
  }
}
