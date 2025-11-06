import 'dart:math';

import 'package:async/async.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_misc/text_loading_shimmer.dart';
import 'package:fluffychat/pangea/common/utils/feedback_model.dart';
import 'package:fluffychat/pangea/translation/full_text_translation_repo.dart';
import 'package:fluffychat/pangea/translation/full_text_translation_request_model.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:flutter/material.dart';

import '../../../widgets/matrix.dart';
import '../../bot/utils/bot_style.dart';
import '../../common/widgets/card_error_widget.dart';

class ITFeedbackCard extends StatefulWidget {
  final FullTextTranslationRequestModel req;

  const ITFeedbackCard(
    this.req, {
    super.key,
  });

  @override
  State<ITFeedbackCard> createState() => ITFeedbackCardController();
}

class ITFeedbackCardController extends State<ITFeedbackCard> {
  final FeedbackModel<String> _feedbackModel = FeedbackModel<String>();

  @override
  void initState() {
    super.initState();
    _getFeedback();
  }

  @override
  void dispose() {
    _feedbackModel.dispose();
    super.dispose();
  }

  Future<void> _getFeedback() async {
    _feedbackModel.setState(FeedbackLoading());
    final result = await FullTextTranslationRepo.get(
      MatrixState.pangeaController.userController.accessToken,
      widget.req,
    ).timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        return Result.error("Timeout getting translation");
      },
    );

    if (!mounted) return;
    if (result.isError) {
      _feedbackModel.setState(
        FeedbackError<String>(result.error.toString()),
      );
    } else {
      _feedbackModel.setState(
        FeedbackLoaded<String>(result.result!.bestTranslation),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _feedbackModel,
      builder: (context, _) {
        final state = _feedbackModel.state;
        if (state is FeedbackError) {
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
                widget.req.text,
                style: BotStyle.text(context),
              ),
              Text(
                "≈",
                style: BotStyle.text(context),
              ),
              _feedbackModel.state is FeedbackLoaded
                  ? Text(
                      (state as FeedbackLoaded<String>).value,
                      style: BotStyle.text(context),
                    )
                  : TextLoadingShimmer(
                      width: min(
                        140,
                        10.0 * widget.req.text.length,
                      ),
                    ),
            ],
          ),
        );
      },
    );
  }
}
