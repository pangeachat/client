import 'dart:math';

import 'package:flutter/material.dart';

import 'package:async/async.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_misc/text_loading_shimmer.dart';
import 'package:fluffychat/pangea/translation/full_text_translation_repo.dart';
import 'package:fluffychat/pangea/translation/full_text_translation_request_model.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import '../../../widgets/matrix.dart';
import '../../bot/utils/bot_style.dart';
import '../../common/widgets/card_error_widget.dart';

class ITFeedbackCard extends StatelessWidget {
  final FullTextTranslationRequestModel req;

  const ITFeedbackCard(
    this.req, {
    super.key,
  });

  Future<Result<String>> _getFeedback() {
    return FullTextTranslationRepo.get(
      MatrixState.pangeaController.userController.accessToken,
      req,
    ).timeout(
      const Duration(seconds: 10),
      onTimeout: () => Result.error("Timeout getting translation"),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Result<String>>(
      future: _getFeedback(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return CardErrorWidget(L10n.of(context).errorFetchingDefinition);
        }

        return Container(
          constraints: const BoxConstraints(maxWidth: 300),
          alignment: Alignment.center,
          child: Wrap(
            spacing: 10,
            alignment: WrapAlignment.center,
            children: [
              Text(
                req.text,
                style: BotStyle.text(context),
              ),
              Text(
                "≈",
                style: BotStyle.text(context),
              ),
              snapshot.hasData
                  ? Text(
                      snapshot.data!.result!,
                      style: BotStyle.text(context),
                    )
                  : TextLoadingShimmer(
                      width: min(
                        140,
                        10.0 * req.text.length,
                      ),
                    ),
            ],
          ),
        );
      },
    );
  }
}
