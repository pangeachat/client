import 'dart:convert';
import 'dart:developer';

import 'package:flutter/foundation.dart';

import 'package:async/async.dart';
import 'package:http/http.dart';

import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/languages/language_model.dart';
import '../common/network/requests.dart';

class LanguageRepo {
  static Future<Result<List<LanguageModel>>> get() async {
    try {
      final languages = await _fetch();
      return Result.value(languages);
    } catch (e) {
      return Result.error(e);
    }
  }

  static Future<List<LanguageModel>> _fetch() async {
    final Requests req = Requests(
      choreoApiKey: Environment.choreoApiKey,
    );

    final Response res = await req.get(
      url: PApiUrls.getLanguages,
    );

    if (res.statusCode != 200) {
      throw Exception(
        'Failed to fetch languages: ${res.statusCode} ${res.reasonPhrase}',
      );
    }

    return (jsonDecode(utf8.decode(res.bodyBytes)) as List)
        .map((e) {
          try {
            return LanguageModel.fromJson(e);
          } catch (err, stack) {
            debugger(when: kDebugMode);
            ErrorHandler.logError(e: err, s: stack, data: e);
            return null;
          }
        })
        .whereType<LanguageModel>()
        .toList();
  }
}
