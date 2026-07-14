import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:async/async.dart';
import 'package:diacritic/diacritic.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_level_enum.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_model.dart';
import 'package:fluffychat/features/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/widgets/feedback_dialog.dart';
import 'package:fluffychat/pangea/common/widgets/feedback_response_dialog.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_response.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_provider.dart';
import 'package:fluffychat/pangea/morphs/morph_features_and_tags.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/analytics_download_button.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/construct_analytics_details/morph_details_view.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/construct_analytics_details/vocab_analytics_details_view.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/morph_analytics_list_view.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/vocab_analytics_list_view.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/phonetic_transcription/pt_v2_models.dart';
import 'package:fluffychat/routes/chat/events/token_info_feedback/show_token_feedback_dialog.dart';
import 'package:fluffychat/routes/chat/events/token_info_feedback/token_info_feedback_request.dart';
import 'package:fluffychat/utils/navigation_util.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/announcing_snackbar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class ConstructAnalyticsView extends StatefulWidget {
  final ConstructTypeEnum view;
  final ConstructIdentifier? construct;
  final bool showPracticeButton;
  final Widget closeButton;

  const ConstructAnalyticsView({
    super.key,
    required this.view,
    required this.closeButton,
    this.construct,
    this.showPracticeButton = false,
  });

  @override
  ConstructAnalyticsViewState createState() => ConstructAnalyticsViewState();
}

class ConstructAnalyticsViewState extends State<ConstructAnalyticsView> {
  final TextEditingController searchController = TextEditingController();
  final List<ConstructIdentifier> selectedConstructs = [];

  MorphFeaturesAndTags morphs =
      GrammarConstructsProvider.defaultFeaturesAndTags;

  List<ConstructUses>? vocab;

  /// True until the first vocab+grammar fetch (`_setAnalyticsData`) completes.
  /// `analyticsService.isInitializing` only covers the underlying service sync;
  /// the per-type aggregation runs after that, so without this flag the panel
  /// renders an empty list before the data lands and looks like "no data"
  /// rather than "loading" (#7078). Stays false across later stream-driven
  /// refreshes so they update in place instead of flashing a spinner.
  bool loadingAnalytics = true;

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

  LanguageModel? get _l2 => MatrixState.pangeaController.userController.userL2;

  Future<void> _setAnalyticsData() async {
    final l2 = _l2;
    if (l2 == null) {
      ErrorHandler.logError(
        e: "No L2 language set for user",
        m: "Cannot set analytics data",
        data: {"view": widget.view, "construct": widget.construct},
        level: SentryLevel.warning,
      );
      if (mounted && loadingAnalytics) {
        setState(() => loadingAnalytics = false);
      }
      return;
    }
    final future = <Future>[_setMorphs(), _setVocab(l2.langCodeShort)];
    await Future.wait(future);
    if (mounted && loadingAnalytics) {
      setState(() => loadingAnalytics = false);
    }
  }

  void _onConstructUpdate(AnalyticsStreamUpdate update) {
    if (update.blockedConstructs != null) {
      _onBlockConstruct(update);
    } else {
      _setAnalyticsData();
    }
  }

  /// Close this construct detail. As a dialog it pops; as the world_v2 right-
  /// column token there is nothing to pop to, so fall back to the analytics
  /// summary for this construct type instead of dead-ending on the loading page
  /// (#7076).
  void _close() => NavigationUtil.popOrGo(
    context,
    WorkspaceNav.closeConstructDetail(
      GoRouterState.of(context).uri,
      widget.view,
    ),
  );

  void _onBlockConstruct(AnalyticsStreamUpdate update) {
    final blocked = update.blockedConstructs;
    if (blocked == null) return;
    vocab?.removeWhere((e) => blocked.contains(e.id));
    if (widget.view == ConstructTypeEnum.vocab) {
      if (widget.construct == null) {
        setState(() {});
      }

      if (blocked.contains(widget.construct)) {
        _close();
      }
    }
  }

  Future<void> _setVocab(String language) async {
    try {
      final analyticsService = Matrix.of(context).analyticsDataService;
      final data = await analyticsService.getAggregatedConstructs(
        ConstructTypeEnum.vocab,
        language,
      );

      vocab = data.values.toList();
      vocab!.sort((a, b) {
        final normalizedA = removeDiacritics(a.lemma).toLowerCase();
        final normalizedB = removeDiacritics(b.lemma).toLowerCase();
        return normalizedA.compareTo(normalizedB);
      });
    } finally {
      if (mounted) setState(() {});
    }
  }

  Future<void> _setMorphs() async {
    morphs = await GrammarConstructsProvider.fetchFeaturesAndTags();
    if (mounted) setState(() {});
  }

  Future<Result<void>?> blockConstructs(
    List<ConstructIdentifier> constructs,
  ) async {
    final resp = await showOkCancelAlertDialog(
      context: context,
      title: L10n.of(context).areYouSure,
      message: L10n.of(context).blockLemmaConfirmation,
      isDestructive: true,
    );

    if (resp != OkCancelResult.ok) return null;
    return showFutureLoadingDialog(
      context: context,
      future: () => Matrix.of(
        context,
      ).analyticsDataService.updateService.blockConstructs(constructs),
    );
  }

  Future<void> blockSelectedConstructs() async {
    final res = await blockConstructs(selectedConstructs);
    if (res == null || res.isError) return;
    clearSelectedConstructs();
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

  void toggleSelectedConstruct(ConstructIdentifier construct) {
    setState(() {
      if (selectedConstructs.contains(construct)) {
        selectedConstructs.remove(construct);
      } else {
        selectedConstructs.add(construct);
      }
    });
  }

  void clearSelectedConstructs() {
    setState(() {
      selectedConstructs.clear();
    });
  }

  bool get selectMode => selectedConstructs.isNotEmpty;

  Future<void> onFlagVocabDetails(
    PangeaToken token,
    LemmaInfoResponse lemmaInfo,
    PTRequest ptRequest,
    PTResponse ptResponse,
  ) async {
    final l2 = _l2;
    if (l2 == null) return;
    final requestData = TokenInfoFeedbackRequestData(
      userId: Matrix.of(context).client.userID!,
      detectedLanguage: l2.langCode,
      tokens: [token],
      selectedToken: 0,
      wordCardL1: MatrixState.pangeaController.userController.userL1Code!,
      lemmaInfo: lemmaInfo,
      ptRequest: ptRequest,
      ptResponse: ptResponse,
    );

    await TokenFeedbackUtil.showTokenFeedbackDialog(
      context,
      requestData: requestData,
      langCode: l2.langCode,
      onUpdated: () => reloadNotifier.value++,
    );
  }

  Future<void> onFlagGrammarDetails() async {
    if (widget.view != ConstructTypeEnum.morph) return;

    final construct = widget.construct;
    final feature = construct?.category;
    if (feature == null) return;

    final l10n = L10n.of(context);
    await showDialog(
      context: context,
      builder: (dialogContext) => FeedbackDialog(
        title: l10n.grammarFeedbackDialogTitle,
        onSubmit: (feedback) async {
          Navigator.of(dialogContext).pop();
          final result = await showFutureLoadingDialog(
            context: context,
            future: () => GrammarConstructsProvider.submitTagFeedback(
              feature: feature,
              feedback: feedback,
            ),
          );
          if (!mounted || result.isError) return;
          setState(() {});
          await showDialog(
            context: context,
            builder: (context) => FeedbackResponseDialog(
              title: l10n.grammarFeedbackDialogTitle,
              feedback: L10n.of(context).grammarFeedbackSubmittedDesc,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final analyticsService = Matrix.of(context).analyticsDataService;
    final title = widget.construct != null
        ? null
        : switch (widget.view) {
            ConstructTypeEnum.morph => L10n.of(context).grammar,
            ConstructTypeEnum.vocab => L10n.of(context).vocab,
          };

    final showDownload = kIsWeb && widget.construct == null;
    final showReport =
        widget.view == ConstructTypeEnum.morph && widget.construct != null;

    return Scaffold(
      appBar: AppBar(
        leading: Center(child: widget.closeButton),
        title: title != null
            ? Text(
                title,
                style: FluffyThemes.isColumnMode(context)
                    ? Theme.of(context).textTheme.titleLarge
                    : Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
              )
            : null,
        centerTitle: false,
        titleSpacing: 0,
        actions: [
          if (showDownload) DownloadAnalyticsButton(),
          if (showReport)
            IconButton(
              color: Theme.of(context).iconTheme.color,
              icon: const Icon(Icons.flag_outlined),
              tooltip: L10n.of(context).reportGrammarIssueTooltip,
              onPressed: onFlagGrammarDetails,
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsetsGeometry.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: analyticsService.isInitializing || loadingAnalytics
                    ? Center(child: CircularProgressIndicator.adaptive())
                    : widget.view == ConstructTypeEnum.morph
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
          widget.construct == null && widget.showPracticeButton
          ? _PracticeButton(view: widget.view)
          : null,
    );
  }
}

class _PracticeButton extends StatelessWidget {
  final ConstructTypeEnum view;
  const _PracticeButton({required this.view});

  void _showSnackbar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBarAnnounced(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final analyticsService = Matrix.of(context).analyticsDataService;
    if (analyticsService.isInitializing) {
      return FloatingActionButton.extended(
        onPressed: () =>
            _showSnackbar(context, L10n.of(context).loadingPleaseWait),
        label: Text(view.practiceButtonText(context)),
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(
          context,
        ).colorScheme.onSurface.withValues(alpha: 0.5),
      );
    }

    final count = analyticsService.numConstructs(view);
    final enabled = count >= 10;

    return FloatingActionButton.extended(
      onPressed: enabled
          // world_v2: practice opens as a right-column `practice:<type>` panel
          // that takes over the analytics surface (it is not a route). See
          // routing.instructions.md.
          ? () => context.go(
              WorkspaceNav.openPractice(
                GoRouterState.of(context).uri,
                // Canonical token vocabulary: `grammar`/`vocab`, never the
                // legacy `morph` (ConstructTypeEnum is the one source of truth).
                view,
              ),
            )
          : () => _showSnackbar(context, L10n.of(context).notEnoughToPractice),
      backgroundColor: enabled
          ? null
          : Theme.of(context).colorScheme.surfaceContainer,
      foregroundColor: enabled
          ? null
          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(enabled ? Symbols.fitness_center : Icons.lock_outline, size: 18),
          const SizedBox(width: 4),
          Text(view.practiceButtonText(context)),
        ],
      ),
    );
  }
}
