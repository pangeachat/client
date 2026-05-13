import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_misc/text_loading_shimmer.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/languages/language_constants.dart';
import 'package:fluffychat/pangea/morphs/get_grammar_copy.dart';
import 'package:fluffychat/pangea/morphs/grammar_construct_meaning_repo.dart';
import 'package:fluffychat/pangea/morphs/grammar_construct_meaning_request.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_request.dart';
import 'package:fluffychat/pangea/morphs/localized_grammar_constructs_repo.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

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

  String get _targetLanguage =>
      MatrixState.pangeaController.userController.userL2Code ??
      LanguageKeys.defaultLanguage;

  String get _userL1 =>
      MatrixState.pangeaController.userController.userL1Code ??
      LanguageKeys.defaultLanguage;

  GrammarConstructsRequest get _constructsRequest => GrammarConstructsRequest(
    targetLanguage: _targetLanguage,
    userL1: _userL1,
  );

  GrammarConstructMeaningRequest get _meaningRequest =>
      GrammarConstructMeaningRequest(
        targetLanguage: _targetLanguage,
        userL1: _userL1,
        feature: widget.feature.name,
      );

  Future<void> _loadMorphMeaning() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _definition = null;
      });
    }

    final response = await _morphMeaning();
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

  Future<String?> _morphMeaning() async {
    String? description;
    final morphMeaningResult = await GrammarConstructMeaningRepo.instance.get(
      _meaningRequest,
      timeout: Duration(seconds: 10),
    );

    description = morphMeaningResult.result?.getTag(widget.tag)?.description;
    if (description != null) return description;

    final constructsResult = await LocalizedGrammarConstructsRepo.instance.get(
      _constructsRequest,
      timeout: Duration(seconds: 10),
    );

    description = constructsResult.result
        ?.getFeature(widget.feature.name)
        ?.getTag(widget.tag)
        ?.description;

    if (description != null) return description;
    return null;
  }

  void _toggleEditMode(bool value) => setState(() => _editMode = value);

  Future<void> editMorphMeaning(String userEdit) async {
    final truncatedEdit = userEdit.length > maxCharacters
        ? userEdit.substring(0, maxCharacters)
        : userEdit;

    final futures = [
      GrammarConstructMeaningRepo.instance.setMeaning(
        request: _meaningRequest,
        tag: widget.tag,
        description: truncatedEdit,
      ),

      LocalizedGrammarConstructsRepo.instance.setMeaning(
        request: _constructsRequest,
        feature: widget.feature.name,
        tag: widget.tag,
        description: truncatedEdit,
      ),
    ];

    try {
      await Future.wait(futures).timeout(Duration(seconds: 10));
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
