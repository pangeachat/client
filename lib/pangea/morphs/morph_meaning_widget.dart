import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_provider.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_response.dart';
import 'package:fluffychat/widgets/text_loading_shimmer.dart';

class MorphMeaningWidget extends StatefulWidget {
  final String feature;
  final String tag;
  final TextStyle? style;
  final bool blankErrorFeedback;

  /// Bumped by an ancestor when the cached meaning for this (feature, tag) is
  /// regenerated in place — e.g. after grammar-meaning feedback is applied
  /// (#7676). The (feature, tag) identity is unchanged, so `didUpdateWidget`'s
  /// identity check can't catch it; listening to this notifier re-fetches the
  /// now-updated copy. Mirrors LemmaMeaningBuilder / PhoneticTranscriptionBuilder.
  final ValueNotifier<int>? reloadNotifier;

  const MorphMeaningWidget({
    super.key,
    required this.feature,
    required this.tag,
    this.style,
    this.blankErrorFeedback = false,
    this.reloadNotifier,
  });

  @override
  MorphMeaningWidgetState createState() => MorphMeaningWidgetState();
}

class MorphMeaningWidgetState extends State<MorphMeaningWidget> {
  final ValueNotifier<AsyncState<GrammarTag>> _loader = ValueNotifier(
    AsyncLoading(),
  );

  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _loadMorphMeaning();
    widget.reloadNotifier?.addListener(_loadMorphMeaning);
  }

  @override
  void didUpdateWidget(covariant MorphMeaningWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadNotifier != widget.reloadNotifier) {
      oldWidget.reloadNotifier?.removeListener(_loadMorphMeaning);
      widget.reloadNotifier?.addListener(_loadMorphMeaning);
    }
    if (oldWidget.tag != widget.tag || oldWidget.feature != widget.feature) {
      _loadMorphMeaning();
    }
  }

  @override
  void dispose() {
    widget.reloadNotifier?.removeListener(_loadMorphMeaning);
    _loader.dispose();
    super.dispose();
  }

  void _setLoaderValue(AsyncState<GrammarTag> value, int generation) {
    if (mounted && _generation == generation) {
      _loader.value = value;
    }
  }

  Future<void> _loadMorphMeaning() async {
    _generation++;
    final generation = _generation;

    _setLoaderValue(AsyncLoading(), generation);

    try {
      final tag = await GrammarConstructsProvider.fetchTag(
        feature: widget.feature,
        tag: widget.tag,
      );

      if (tag == null) throw 'Tag not found';
      _setLoaderValue(AsyncLoaded(tag), generation);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'feature': widget.feature, 'tag': widget.tag},
      );
      _setLoaderValue(AsyncError(e), generation);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: _loader,
      builder: (context, loaderState, _) => switch (loaderState) {
        AsyncLoading() || AsyncIdle() => const TextLoadingShimmer(),
        AsyncError() => Text(
          textAlign: TextAlign.center,
          L10n.of(context).meaningNotFound,
          style: widget.style,
        ),
        AsyncLoaded(value: final tag) => Text(
          textAlign: TextAlign.center,
          tag.description,
          style: widget.style,
        ),
      },
    );
  }
}
