import 'dart:async';

import 'package:flutter/material.dart';

import 'package:diacritic/diacritic.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/pangea/analytics_details_popup/morph_analytics_list_view.dart';
import 'package:fluffychat/pangea/analytics_details_popup/morph_details_view.dart';
import 'package:fluffychat/pangea/analytics_details_popup/vocab_analytics_details_view.dart';
import 'package:fluffychat/pangea/analytics_details_popup/vocab_analytics_list_view.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_model.dart';
import 'package:fluffychat/pangea/analytics_summary/learning_progress_indicators.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/constructs/construct_level_enum.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_response.dart';
import 'package:fluffychat/pangea/morphs/default_morph_mapping.dart';
import 'package:fluffychat/pangea/morphs/morph_models.dart';
import 'package:fluffychat/pangea/morphs/morph_repo.dart';
import 'package:fluffychat/pangea/token_info_feedback/show_token_feedback_dialog.dart';
import 'package:fluffychat/pangea/token_info_feedback/token_info_feedback_request.dart';
import 'package:fluffychat/widgets/matrix.dart';

class ConstructAnalyticsView extends StatefulWidget {
  const ConstructAnalyticsView({
    super.key,
    required this.view,
    this.construct,
  });

  final ConstructTypeEnum view;
  final ConstructIdentifier? construct;

  @override
  ConstructAnalyticsViewState createState() => ConstructAnalyticsViewState();
}

class ConstructAnalyticsViewState extends State<ConstructAnalyticsView> {
  final TextEditingController searchController = TextEditingController();

  MorphFeaturesAndTags morphs = defaultMorphMapping;
  List<MorphFeature> features = defaultMorphMapping.displayFeatures;

  List<ConstructUses>? vocab;

  bool isSearching = false;
  FocusNode searchFocusNode = FocusNode();
  ConstructLevelEnum? selectedConstructLevel;
  StreamSubscription<AnalyticsStreamUpdate>? _constructUpdateSub;
  final ValueNotifier<int> reloadNotifier = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _setAnalyticsData();

    searchController.addListener(() {
      if (mounted) setState(() {});
    });

    _constructUpdateSub = Matrix.of(context)
        .analyticsDataService
        .updateDispatcher
        .constructUpdateStream
        .stream
        .listen(_onConstructUpdate);
  }

  @override
  void dispose() {
    searchController.dispose();
    _constructUpdateSub?.cancel();
    searchFocusNode.dispose();
    reloadNotifier.dispose();
    super.dispose();
  }

  Future<void> _setAnalyticsData() async {
    final future = <Future>[
      _setMorphs(),
      _setVocab(),
    ];
    await Future.wait(future);
  }

  void _onConstructUpdate(AnalyticsStreamUpdate update) {
    if (update.blockedConstruct != null) {
      _onBlockConstruct(update);
    } else {
      _setAnalyticsData();
    }
  }

  void _onBlockConstruct(AnalyticsStreamUpdate update) {
    final blocked = update.blockedConstruct;
    if (blocked == null) return;
    vocab?.removeWhere((e) => e.id == blocked);
    if (widget.view == ConstructTypeEnum.vocab && widget.construct == null) {
      setState(() {});
    }
  }

  Future<void> _setVocab() async {
    try {
      final analyticsService = Matrix.of(context).analyticsDataService;
      final data = await analyticsService
          .getAggregatedConstructs(ConstructTypeEnum.vocab);

      vocab = data.values.toList();
      vocab!.sort(
        (a, b) {
          final normalizedA = removeDiacritics(a.lemma).toLowerCase();
          final normalizedB = removeDiacritics(b.lemma).toLowerCase();
          return normalizedA.compareTo(normalizedB);
        },
      );
    } finally {
      if (mounted) setState(() {});
    }
  }

  Future<void> _setMorphs() async {
    try {
      final resp = await MorphsRepo.get();
      morphs = resp;
      features = resp.displayFeatures;
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {"l2": MatrixState.pangeaController.userController.userL2},
      );
    } finally {
      features.sort(
        (a, b) => morphFeatureSortOrder
            .indexOf(a.feature)
            .compareTo(morphFeatureSortOrder.indexOf(b.feature)),
      );
      if (mounted) setState(() {});
    }
  }

  void setSelectedConstructLevel(ConstructLevelEnum level) {
    setState(() {
      selectedConstructLevel = selectedConstructLevel == level ? null : level;
    });
  }

  void toggleSearching() {
    setState(() {
      isSearching = !isSearching;
      selectedConstructLevel = null;
      searchController.clear();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isSearching) {
        FocusScope.of(context).requestFocus(searchFocusNode);
      } else {
        searchFocusNode.unfocus();
      }
    });
  }

  Future<void> onFlagTokenInfo(
    PangeaToken token,
    LemmaInfoResponse lemmaInfo,
    String phonetics,
  ) async {
    final requestData = TokenInfoFeedbackRequestData(
      userId: Matrix.of(context).client.userID!,
      detectedLanguage: MatrixState.pangeaController.userController.userL2Code!,
      tokens: [token],
      selectedToken: 0,
      wordCardL1: MatrixState.pangeaController.userController.userL1Code!,
      lemmaInfo: lemmaInfo,
      phonetics: phonetics,
    );

    await TokenFeedbackUtil.showTokenFeedbackDialog(
      context,
      requestData: requestData,
      langCode: MatrixState.pangeaController.userController.userL2Code!,
      onUpdated: () => reloadNotifier.value++,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsetsGeometry.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.construct == null)
                LearningProgressIndicators(
                  selected: widget.view.indicator,
                ),
              Expanded(
                child: widget.view == ConstructTypeEnum.morph
                    ? widget.construct == null
                        ? MorphAnalyticsListView(controller: this)
                        : MorphDetailsView(constructId: widget.construct!)
                    : widget.construct == null
                        ? VocabAnalyticsListView(controller: this)
                        : VocabDetailsView(
                            constructId: widget.construct!,
                            controller: this,
                          ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton:
          widget.construct == null ? _PracticeButton(view: widget.view) : null,
    );
  }
}

class _PracticeButton extends StatelessWidget {
  final ConstructTypeEnum view;
  const _PracticeButton({required this.view});

  void _showSnackbar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final analyticsService = Matrix.of(context).analyticsDataService;
    if (analyticsService.isInitializing) {
      return FloatingActionButton.extended(
        onPressed: () => _showSnackbar(
          context,
          L10n.of(context).loadingPleaseWait,
        ),
        label: Text(view.practiceButtonText(context)),
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor:
            Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
      );
    }

    final count = analyticsService.numConstructs(view);
    final enabled = count >= 10;

    return FloatingActionButton.extended(
      onPressed: enabled
          ? () => context.go("/rooms/analytics/${view.name}/practice")
          : () => _showSnackbar(
                context,
                L10n.of(context).notEnoughToPractice,
              ),
      backgroundColor:
          enabled ? null : Theme.of(context).colorScheme.surfaceContainer,
      foregroundColor: enabled
          ? null
          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            enabled ? Symbols.fitness_center : Icons.lock_outline,
            size: 18,
          ),
          const SizedBox(width: 4),
          Text(view.practiceButtonText(context)),
        ],
      ),
    );
  }
}
