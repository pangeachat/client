import 'package:flutter/material.dart';

import 'package:collection/collection.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_details_popup/analytics_details_usage_content.dart';
import 'package:fluffychat/pangea/analytics_details_popup/word_text_with_audio_button.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/constructs/construct_level_enum.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/pangea/lemmas/construct_xp_widget.dart';
import 'package:fluffychat/pangea/toolbar/word_card/word_zoom_widget.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Displays information about selected lemma, and its usage
class VocabDetailsView extends StatefulWidget {
  final ConstructIdentifier constructId;

  const VocabDetailsView({
    super.key,
    required this.constructId,
  });

  @override
  State<VocabDetailsView> createState() => VocabDetailsViewState();
}

class VocabDetailsViewState extends State<VocabDetailsView> {
  ConstructIdentifier get constructId => widget.constructId;

  final ValueNotifier<String?> _emojiNotifier = ValueNotifier<String?>(null);

  @override
  void initState() {
    super.initState();
    _emojiNotifier.value = constructId.userLemmaInfo.emojis?.firstOrNull;
  }

  @override
  void dispose() {
    _emojiNotifier.dispose();
    super.dispose();
  }

  List<String> get forms =>
      MatrixState.pangeaController.getAnalytics.constructListModel
          .getConstructUsesByLemma(constructId.lemma)
          .map((e) => e.uses)
          .expand((element) => element)
          .map((e) => e.form?.toLowerCase())
          .toSet()
          .whereType<String>()
          .toList();

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
            setEmoji: (emoji) => _emojiNotifier.value = emoji,
          ),
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: ConstructXpWidget(
                  icon: ValueListenableBuilder(
                    valueListenable: _emojiNotifier,
                    builder: (context, emoji, __) => Text(
                      emoji ?? "-",
                      style: const TextStyle(fontSize: 24.0),
                    ),
                  ),
                  level: construct.lemmaCategory,
                  points: construct.points,
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
