import 'package:flutter/material.dart';

import 'package:collection/collection.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_details_popup/analytics_details_usage_content.dart';
import 'package:fluffychat/pangea/analytics_details_popup/construct_xp_progress_bar.dart';
import 'package:fluffychat/pangea/analytics_details_popup/word_text_with_audio_button.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/constructs/construct_level_enum.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/pangea/lemmas/lemma.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_response.dart';
import 'package:fluffychat/pangea/token_info_feedback/show_token_feedback_dialog.dart';
import 'package:fluffychat/pangea/token_info_feedback/token_info_feedback_request.dart';
import 'package:fluffychat/pangea/toolbar/word_card/word_zoom_widget.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Displays information about selected lemma, and its usage
class VocabDetailsView extends StatelessWidget {
  final ConstructIdentifier constructId;

  const VocabDetailsView({
    super.key,
    required this.constructId,
  });

  Future<void> _blockLemma(BuildContext context) async {
    final resp = await showOkCancelAlertDialog(
      context: context,
      title: L10n.of(context).areYouSure,
      message: L10n.of(context).blockLemmaConfirmation,
      isDestructive: true,
    );

    if (resp != OkCancelResult.ok) return;
    final res = await showFutureLoadingDialog(
      context: context,
      future: () => Matrix.of(context)
          .analyticsDataService
          .updateService
          .blockConstruct(constructId),
    );

    if (!res.isError) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final analyticsService = Matrix.of(context).analyticsDataService;
    return FutureBuilder(
      future: analyticsService.getConstructUse(constructId),
      builder: (context, snapshot) {
        final construct = snapshot.data;
        final level = construct?.lemmaCategory ?? ConstructLevelEnum.seeds;

        final Color textColor =
            (Theme.of(context).brightness != Brightness.light
                ? level.color(context)
                : level.darkColor(context));

        final forms = construct?.forms ?? [];
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
                  onClose: Navigator.of(context).pop,
                  onFlagTokenInfo:
                      (LemmaInfoResponse lemmaInfo, String phonetics) {
                    final requestData = TokenInfoFeedbackRequestData(
                      userId: Matrix.of(context).client.userID!,
                      detectedLanguage: MatrixState
                          .pangeaController.userController.userL2Code!,
                      tokens: [token],
                      selectedToken: 0,
                      wordCardL1: MatrixState
                          .pangeaController.userController.userL1Code!,
                      lemmaInfo: lemmaInfo,
                      phonetics: phonetics,
                    );

                    TokenFeedbackUtil.showTokenFeedbackDialog(
                      context,
                      requestData: requestData,
                      langCode: MatrixState
                          .pangeaController.userController.userL2Code!,
                    );
                  },
                  maxWidth: double.infinity,
                ),
              ),
              if (construct != null)
                Column(
                  spacing: 20.0,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: ConstructXPProgressBar(
                        construct: constructId,
                      ),
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
                        AnalyticsDetailsUsageContent(
                          construct: construct,
                        ),
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
                          onTap: () => _blockLemma(context),
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
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(width: 6.0),
          ...forms.mapIndexed(
            (i, form) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                WordTextWithAudioButton(
                  text: form,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: textColor,
                      ),
                  uniqueID: "$form-$lemma-$i",
                  langCode:
                      MatrixState.pangeaController.userController.userL2Code!,
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
