import 'dart:async';

import 'package:flutter/material.dart';

import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_misc/text_loading_shimmer.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_provider.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_response.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';

class MorphMeaningWidget extends StatefulWidget {
  final MorphFeaturesEnum feature;
  final String tag;
  final TextStyle? style;
  final bool blankErrorFeedback;

  const MorphMeaningWidget({
    super.key,
    required this.feature,
    required this.tag,
    this.style,
    this.blankErrorFeedback = false,
  });

  @override
  MorphMeaningWidgetState createState() => MorphMeaningWidgetState();
}

class MorphMeaningWidgetState extends State<MorphMeaningWidget> {
  GrammarTag? _tag;
  bool _isLoading = true;
  bool _editMode = false;

  @override
  void initState() {
    super.initState();
    _loadMorphMeaning();
  }

  @override
  void didUpdateWidget(covariant MorphMeaningWidget oldWidget) {
    if (oldWidget.tag != widget.tag || oldWidget.feature != widget.feature) {
      _loadMorphMeaning();
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  final _controller = TextEditingController();

  String get _blankDescription =>
      widget.blankErrorFeedback ? '' : L10n.of(context).meaningNotFound;

  void _setEditMode(bool value) => setState(() => _editMode = value);

  Future<void> _loadMorphMeaning() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _tag = null;
      });
    }

    final tag = await GrammarConstructsProvider.fetchTag(
      feature: widget.feature.name,
      tag: widget.tag,
    );

    final description = tag?.description ?? _blankDescription;
    _controller.text = description;

    if (mounted) {
      setState(() {
        _isLoading = false;
        _tag = tag;
      });
    }
  }

  Future<void> _setMorphMeaning() async {
    final text = _controller.text;
    if (text.isEmpty || text == _tag?.description) {
      return;
    }

    try {
      await GrammarConstructsProvider.setTagDescription(
        feature: widget.feature.name,
        tag: widget.tag,
        description: text,
      ).timeout(Duration(seconds: 10));
    } catch (e, s) {
      if (e is TimeoutException) {
        ErrorHandler.logError(e: e, s: s, data: {}, level: SentryLevel.warning);
      }
    }

    if (mounted) {
      _setEditMode(false);
      _loadMorphMeaning();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const TextLoadingShimmer();
    }

    if (_editMode && _tag != null) {
      return MorphEditView(
        tag: _tag!,
        controller: _controller,
        exit: () => _setEditMode(false),
        save: _setMorphMeaning,
      );
    }

    return Tooltip(
      triggerMode: TooltipTriggerMode.tap,
      message: L10n.of(context).doubleClickToEdit,
      child: GestureDetector(
        onLongPress: () => _setEditMode(true),
        onDoubleTap: () => _setEditMode(true),
        child: Text(
          textAlign: TextAlign.center,
          _tag?.description ?? L10n.of(context).meaningNotFound,
          style: widget.style,
        ),
      ),
    );
  }
}

class MorphEditView extends StatelessWidget {
  final GrammarTag tag;
  final VoidCallback exit;
  final VoidCallback save;
  final TextEditingController controller;

  const MorphEditView({
    required this.tag,
    required this.exit,
    required this.save,
    required this.controller,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: 10.0,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          "${L10n.of(context).pangeaBotIsFallible} ${L10n.of(context).whatIsMeaning(tag.title, '')}",
          textAlign: TextAlign.center,
          style: const TextStyle(fontStyle: FontStyle.italic),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: TextField(minLines: 1, maxLines: 3, controller: controller),
        ),
        Row(
          spacing: 10.0,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: exit,
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10.0),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: Text(L10n.of(context).cancel),
            ),
            ElevatedButton(
              onPressed: save,
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10.0),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: Text(L10n.of(context).saveChanges),
            ),
          ],
        ),
      ],
    );
  }
}
