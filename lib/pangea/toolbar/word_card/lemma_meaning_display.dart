import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_misc/text_loading_shimmer.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/lemmas/lemma_meaning_builder.dart';

class LemmaMeaningDisplay extends StatelessWidget {
  final String langCode;
  final ConstructIdentifier constructId;
  final String text;

  const LemmaMeaningDisplay({
    super.key,
    required this.langCode,
    required this.constructId,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return LemmaMeaningBuilder(
      langCode: langCode,
      constructId: constructId,
      builder: (context, controller) {
        if (controller.isError) {
          return ErrorIndicator(
            message: L10n.of(context).errorFetchingDefinition,
            style: const TextStyle(fontSize: 14.0),
          );
        }

        if (controller.isLoading || controller.lemmaInfo == null) {
          return const TextLoadingShimmer(
            width: 125.0,
            height: 20.0,
          );
        }

        if (constructId.lemma.toLowerCase() == text.toLowerCase()) {
          return Text(
            controller.lemmaInfo!.meaning,
            style: const TextStyle(
              fontSize: 14.0,
            ),
            textAlign: TextAlign.center,
          );
        }

        return RichText(
          text: TextSpan(
            style: DefaultTextStyle.of(context).style.copyWith(
                  fontSize: 14.0,
                ),
            children: [
              TextSpan(
                text: constructId.lemma,
              ),
              const WidgetSpan(
                child: SizedBox(width: 8.0),
              ),
              const TextSpan(text: ":"),
              const WidgetSpan(
                child: SizedBox(width: 8.0),
              ),
              TextSpan(
                text: controller.lemmaInfo!.meaning,
              ),
            ],
          ),
        );
      },
    );
  }
}
