import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';

import 'package:collection/collection.dart';

import 'package:fluffychat/pangea/choreographer/controllers/choreographer.dart';
import 'package:fluffychat/pangea/choreographer/models/span_data.dart';
import 'package:fluffychat/pangea/choreographer/repo/span_data_repo.dart';
import 'package:fluffychat/pangea/choreographer/utils/text_normalization_util.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

class SpanDataController {
  late Choreographer choreographer;
  SpanDataController(this.choreographer);

  SpanData? _getSpan(int matchIndex) {
    if (choreographer.igc.igcTextData == null ||
        choreographer.igc.igcTextData!.matches.isEmpty ||
        matchIndex < 0 ||
        matchIndex >= choreographer.igc.igcTextData!.matches.length) {
      debugger(when: kDebugMode);
      return null;
    }

    /// Retrieves the span data from the `igcTextData` matches at the specified `matchIndex`.
    /// Creates a `SpanDetailsRepoReqAndRes` object with the retrieved span data and other parameters.
    /// Generates a cache key based on the created `SpanDetailsRepoReqAndRes` object.
    return choreographer.igc.igcTextData!.matches[matchIndex].match;
  }

  bool isNormalizationError(int matchIndex) {
    final span = _getSpan(matchIndex);
    if (span == null) return false;

    final correctChoice = span.choices
        ?.firstWhereOrNull(
          (c) => c.isBestCorrection,
        )
        ?.value;

    final errorSpan = span.fullText.substring(
      span.offset,
      span.offset + span.length,
    );

    return correctChoice != null &&
        TextNormalizationUtil.normalizeString(correctChoice) ==
            TextNormalizationUtil.normalizeString(errorSpan);
  }

  Future<void> getSpanDetails(
    int matchIndex, {
    bool force = false,
  }) async {
    final SpanData? span = _getSpan(matchIndex);
    if (span == null || (isNormalizationError(matchIndex) && !force)) return;
    final response = await SpanDataRepo.get(
      choreographer.accessToken,
      request: SpanDetailsRepoReqAndRes(
        userL1: choreographer.l1LangCode!,
        userL2: choreographer.l2LangCode!,
        enableIGC: choreographer.igcEnabled,
        enableIT: choreographer.itEnabled,
        span: span,
      ),
    );

    if (response.result != null) {
      choreographer.igc.igcTextData!.matches[matchIndex].match =
          response.result!.span;
    }

    choreographer.setState();
  }
}
