import 'package:flutter/material.dart';

import 'package:collection/collection.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_details_popup/analytics_details_usage_content.dart';
import 'package:fluffychat/pangea/analytics_details_popup/word_text_with_audio_button.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/constructs/construct_level_enum.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/pangea/toolbar/word_card/word_zoom_widget.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Displays information about selected lemma, and its usage
class VocabDetailsView extends StatelessWidget {
  final ConstructIdentifier constructId;

  const VocabDetailsView({
    super.key,
    required this.constructId,
  });

  List<String> get forms =>
      MatrixState.pangeaController.getAnalytics.constructListModel
          .getConstructUsesByLemma(constructId.lemma)
          .map((e) => e.uses)
          .expand((element) => element)
          .map((e) => e.form?.toLowerCase())
          .toSet()
          .whereType<String>()
          .toList();

  final double _iconSize = 24.0;

  @override
  Widget build(BuildContext context) {
    final construct = constructId.constructUses;
    final Color textColor = (Theme.of(context).brightness != Brightness.light
        ? construct.lemmaCategory.color(context)
        : construct.lemmaCategory.darkColor(context));

    return SingleChildScrollView(
      child: Column(
        spacing: 16.0,
        children: [
          WordZoomWidget(
            token: PangeaTokenText.fromString(constructId.lemma),
            langCode: MatrixState.pangeaController.userController.userL2Code!,
            construct: constructId,
          ),
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  spacing: 16.0,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    construct.lemmaCategory.icon(_iconSize + 6.0),
                    Text(
                      "${construct.points} XP",
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: textColor,
                          ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _VocabForms(
                        lemma: constructId.lemma,
                        forms: forms,
                        textColor: textColor,
                      ),
                    ),
                    AnalyticsDetailsUsageContent(
                      construct: construct,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
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
