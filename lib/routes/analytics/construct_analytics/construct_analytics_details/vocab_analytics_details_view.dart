import 'package:flutter/material.dart';

import 'package:collection/collection.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_level_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_model.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/lemmas/lemma.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_response.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/analytics_details_popup.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/construct_analytics_details/analytics_details_usage_content.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/construct_analytics_details/construct_xp_progress_bar.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/restore_constructs_mixin.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/routes/chat/events/phonetic_transcription/pt_v2_models.dart';
import 'package:fluffychat/routes/chat/toolbar/word_card/word_zoom_widget.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Displays information about selected lemma, and its usage
class VocabDetailsView extends StatelessWidget with ConstructRestorer {
  final ConstructIdentifier constructId;
  final ConstructAnalyticsViewState controller;

  const VocabDetailsView({
    super.key,
    required this.constructId,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final l2 =
        MatrixState.pangeaController.userController.userL2?.langCodeShort;
    final analyticsService = Matrix.of(context).analyticsDataService;
    return FutureBuilder(
      future: l2 != null
          ? analyticsService.getConstructUse(constructId, l2)
          : Future.value(
              ConstructUses(
                uses: [],
                constructType: constructId.type,
                lemma: constructId.lemma,
                category: constructId.category,
              ),
            ),
      builder: (context, snapshot) {
        final construct = snapshot.data;
        final level = construct?.lemmaCategory ?? ConstructLevelEnum.seeds;

        final Color textColor =
            (Theme.of(context).brightness != Brightness.light
            ? level.color(context)
            : level.darkColor(context));

        // Distinct surface forms, deduped case-insensitively by text. Forms
        // are display-only here — audio buttons beside individual forms were
        // removed per phonetic-transcription-v2-design.instructions.md §3.2
        // (form pronunciation lives in chat), so two forms that differ only
        // by POS would render as identical duplicate strings.
        final seenForms = <String>{};
        final forms = <String>[
          for (final use in construct?.uses ?? <OneConstructUse>[])
            if (use.form != null && seenForms.add(use.form!.toLowerCase()))
              use.form!,
        ];

        final tokenText = PangeaTokenText.fromString(constructId.lemma);
        final token = PangeaToken(
          text: tokenText,
          pos: constructId.category,
          morph: {},
          lemma: Lemma(
            text: constructId.lemma,
            form: constructId.lemma,
            saveVocab: true,
          ),
        );

        return MaxWidthBody(
          maxWidth: 600.0,
          showBorder: false,
          child: Column(
            spacing: 20.0,
            children: [
              const SizedBox(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: WordZoomWidget(
                  token: tokenText,
                  langCode:
                      MatrixState.pangeaController.userController.userL2Code!,
                  construct: constructId,
                  pos: constructId.category,
                  // No own close button: the panel header already supplies the
                  // single page X. Passing onClose here drew a redundant second
                  // X inside the word card (#7169).
                  onFlagTokenInfo:
                      (
                        LemmaInfoResponse lemmaInfo,
                        PTRequest ptRequest,
                        PTResponse ptResponse,
                      ) => controller.onFlagVocabDetails(
                        token,
                        lemmaInfo,
                        ptRequest,
                        ptResponse,
                      ),
                  reloadNotifier: controller.reloadNotifier,
                  maxWidth: double.infinity,
                  enableEmojiSelection: true,
                  enableEmojiReactions: false,
                ),
              ),
              if (construct != null)
                Column(
                  spacing: 20.0,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: ConstructXPProgressBar(construct: constructId),
                    ),
                    Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20.0),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _VocabForms(
                              lemma: constructId.lemma,
                              forms: forms,
                              textColor: textColor,
                            ),
                          ),
                        ),
                        AnalyticsDetailsUsageContent(construct: construct),
                        if (Matrix.of(
                          context,
                        ).analyticsDataService.isConstructBlocked(constructId))
                          ListTile(
                            leading: const Icon(
                              Icons.restore_from_trash_outlined,
                            ),
                            title: Text(L10n.of(context).restore),
                            onTap: () =>
                                restoreConstructs(context, [constructId]),
                          )
                        else
                          ListTile(
                            leading: Icon(
                              Icons.delete_outline,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            title: Text(
                              L10n.of(context).delete,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                            onTap: () =>
                                controller.blockConstructs([constructId]),
                          ),
                      ],
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _VocabForms extends StatelessWidget {
  final String lemma;
  final List<String> forms;
  final Color textColor;

  const _VocabForms({
    required this.lemma,
    required this.forms,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Wrap(
        alignment: WrapAlignment.start,
        runAlignment: WrapAlignment.start,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            L10n.of(context).formSectionHeader,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 6.0),
          ...forms.mapIndexed(
            (i, form) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Text(
                    form,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(color: textColor),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (i != forms.length - 1) const Text(",  "),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
