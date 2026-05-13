import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_misc/text_loading_shimmer.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/morphs/get_grammar_copy.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_provider.dart';
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
  bool _editMode = false;

  late TextEditingController _controller;
  static const int maxCharacters = 140;

  String? _definition;
  bool _isLoading = true;

  @override
  void didUpdateWidget(covariant MorphMeaningWidget oldWidget) {
    if (oldWidget.tag != widget.tag || oldWidget.feature != widget.feature) {
      _isLoading = true;
      _loadMorphMeaning();
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _loadMorphMeaning();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _blankDescription =>
      widget.blankErrorFeedback ? '' : L10n.of(context).meaningNotFound;

  Future<void> _loadMorphMeaning() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _definition = null;
      });
    }

    final response = await GrammarConstructsProvider.fetchTagDescription(
      feature: widget.feature.name,
      tag: widget.tag,
    );

    final description = response ?? _blankDescription;
    _controller.text = description.substring(
      0,
      min(description.length, maxCharacters),
    );

    if (mounted) {
      setState(() {
        _isLoading = false;
        _definition = description;
      });
    }
  }

  void _toggleEditMode(bool value) => setState(() => _editMode = value);

  Future<void> editMorphMeaning(String userEdit) async {
    final truncatedEdit = userEdit.length > maxCharacters
        ? userEdit.substring(0, maxCharacters)
        : userEdit;

    try {
      await GrammarConstructsProvider.setTagDescription(
        feature: widget.feature.name,
        tag: widget.tag,
        description: truncatedEdit,
      ).timeout(Duration(seconds: 10));
    } catch (e, s) {
      if (e is TimeoutException) {
        ErrorHandler.logError(e: e, s: s, data: {}, level: SentryLevel.warning);
      }
    }

    _toggleEditMode(false);
    _loadMorphMeaning();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const TextLoadingShimmer();
    }

    if (_editMode) {
      return MorphEditView(
        morphFeature: widget.feature,
        morphTag: widget.tag,
        meaning: _definition ?? "",
        controller: _controller,
        toggleEditMode: _toggleEditMode,
        editMorphMeaning: editMorphMeaning,
      );
    }

    return Tooltip(
      triggerMode: TooltipTriggerMode.tap,
      message: L10n.of(context).doubleClickToEdit,
      child: GestureDetector(
        onLongPress: () => _toggleEditMode(true),
        onDoubleTap: () => _toggleEditMode(true),
        child: Text(
          textAlign: TextAlign.center,
          _definition ?? L10n.of(context).meaningNotFound,
          style: widget.style,
        ),
      ),
    );
  }
}

class MorphEditView extends StatelessWidget {
  final MorphFeaturesEnum morphFeature;
  final String morphTag;
  final String meaning;
  final TextEditingController controller;
  final void Function(bool) toggleEditMode;
  final void Function(String) editMorphMeaning;

  const MorphEditView({
    required this.morphFeature,
    required this.morphTag,
    required this.meaning,
    required this.controller,
    required this.toggleEditMode,
    required this.editMorphMeaning,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          "${L10n.of(context).pangeaBotIsFallible} ${L10n.of(context).whatIsMeaning(getGrammarCopy(category: morphFeature.name, lemma: morphTag, context: context) ?? morphTag, '')}",
          textAlign: TextAlign.center,
          style: const TextStyle(fontStyle: FontStyle.italic),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: TextField(
            minLines: 1,
            maxLines: 3,
            maxLength: MorphMeaningWidgetState.maxCharacters,
            controller: controller,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () => toggleEditMode(false),
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10.0),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: Text(L10n.of(context).cancel),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: () =>
                  controller.text != meaning && controller.text.isNotEmpty
                  ? editMorphMeaning(controller.text)
                  : null,
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
