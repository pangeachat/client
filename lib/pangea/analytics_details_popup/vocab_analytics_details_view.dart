import 'package:flutter/material.dart';

import 'package:collection/collection.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_details_popup/analytics_details_popup_content.dart';
import 'package:fluffychat/pangea/analytics_details_popup/vocab_details_emoji_selector.dart';
import 'package:fluffychat/pangea/analytics_details_popup/word_text_with_audio_button.dart';
import 'package:fluffychat/pangea/common/widgets/shrinkable_text.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/constructs/construct_level_enum.dart';
import 'package:fluffychat/pangea/lemmas/lemma_meaning_widget.dart';
import 'package:fluffychat/pangea/morphs/get_grammar_copy.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/pangea/morphs/morph_icon.dart';
import 'package:fluffychat/pangea/phonetic_transcription/phonetic_transcription_widget.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Displays information about selected lemma, and its usage
class VocabDetailsView extends StatelessWidget {
  final ConstructIdentifier constructId;

  const VocabDetailsView({
    super.key,
    required this.constructId,
  });

  String? get _userL2 =>
      MatrixState.pangeaController.userController.userL2?.langCode;

  final double _iconSize = 24.0;

  @override
  Widget build(BuildContext context) {
    final analyticsService = Matrix.of(context).analyticsDataService;
    return FutureBuilder(
      future: analyticsService.getConstructUse(constructId),
      builder: (context, snapshot) {
        final construct = snapshot.data;
        final level = construct?.lemmaCategory ?? ConstructLevelEnum.seeds;

        final Color textColor = Theme.of(context).brightness != Brightness.light
            ? level.color(context)
            : level.darkColor(context);

        final List<String> forms = construct?.uses
                .map((e) => e.form?.toLowerCase())
                .toSet()
                .whereType<String>()
                .toList() ??
            [];

        return AnalyticsDetailsViewContent(
          construct: construct,
          title: Column(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  return ShrinkableText(
                    text: constructId.lemma,
                    maxWidth: constraints.maxWidth - 40.0,
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                          color: textColor,
                        ),
                  );
                },
              ),
              if (MatrixState.pangeaController.userController.showTranscription)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: PhoneticTranscriptionWidget(
                    text: constructId.lemma,
                    textLanguage:
                        MatrixState.pangeaController.userController.userL2!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: textColor.withAlpha((0.7 * 255).toInt()),
                          fontSize: 18,
                        ),
                    iconSize: _iconSize * 0.8,
                  ),
                ),
            ],
          ),
          subtitle: Column(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 8.0,
                children: [
                  Text(
                    getGrammarCopy(
                          category: "POS",
                          lemma: constructId.category,
                          context: context,
                        ) ??
                        constructId.lemma,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: textColor,
                        ),
                  ),
                  SizedBox(
                    width: _iconSize,
                    height: _iconSize,
                    child: MorphIcon(
                      morphFeature: MorphFeaturesEnum.Pos,
                      morphTag: constructId.category,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16.0),
              Text(
                L10n.of(context).vocabEmoji,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: textColor,
                    ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: VocabDetailsEmojiSelector(constructId),
              ),
            ],
          ),
          headerContent: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              spacing: 8.0,
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: _userL2 == null
                      ? Text(L10n.of(context).meaningNotFound)
                      : LemmaMeaningWidget(
                          constructId: constructId,
                          style: Theme.of(context).textTheme.bodyLarge,
                          leading: TextSpan(
                            text: L10n.of(context).meaningSectionHeader,
                            style:
                                Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                          ),
                        ),
                ),
                Align(
                  alignment: Alignment.topLeft,
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
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(
                                    color: textColor,
                                  ),
                              uniqueID: "$form-${constructId.lemma}-$i",
                              langCode: _userL2!,
                            ),
                            if (i != forms.length - 1) const Text(",  "),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          xpIcon: level.icon(_iconSize + 6.0),
        );
      },
    );
  }
}
