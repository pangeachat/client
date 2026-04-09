import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_misc/text_loading_shimmer.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/lemmas/lemma_meaning_builder.dart';
import 'package:fluffychat/pangea/morphs/get_grammar_copy.dart';

class LemmaMeaningDisplay extends StatelessWidget {
  final String langCode;
  final ConstructIdentifier constructId;
  final String text;
  final Map<String, dynamic> messageInfo;
  final ValueNotifier<int>? reloadNotifier;

  const LemmaMeaningDisplay({
    super.key,
    required this.langCode,
    required this.constructId,
    required this.text,
    required this.messageInfo,
    this.reloadNotifier,
  });

  @override
  Widget build(BuildContext context) {
    return LemmaMeaningBuilder(
      langCode: langCode,
      constructId: constructId,
      messageInfo: messageInfo,
      reloadNotifier: reloadNotifier,
      builder: (context, controller) {
        switch (controller.state) {
          case AsyncError():
            return ErrorIndicator(
              message: L10n.of(context).errorFetchingDefinition,
              style: const TextStyle(fontSize: 14.0),
            );
          case AsyncLoaded(value: final lemmaInfo):
            final pos =
                getGrammarCopy(
                  category: "POS",
                  lemma: constructId.category,
                  context: context,
                ) ??
                L10n.of(context).other;
            final lemma = constructId.lemma;
            return RichText(
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              text: TextSpan(
                style: DefaultTextStyle.of(
                  context,
                ).style.copyWith(fontSize: 14.0),
                children: [
                  TextSpan(
                    text: lemma.length > 50 ? "($pos)" : "$lemma ($pos)",
                  ),
                  const WidgetSpan(child: SizedBox(width: 8.0)),
                  const TextSpan(text: ":"),
                  const WidgetSpan(child: SizedBox(width: 8.0)),
                  TextSpan(text: lemmaInfo.meaning),
                ],
              ),
            );
          default:
            return const TextLoadingShimmer(width: 125.0, height: 20.0);
        }
      },
    );
  }
}
