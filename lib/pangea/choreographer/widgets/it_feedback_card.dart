import 'dart:math';

import 'package:flutter/material.dart';

import 'package:http/http.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_misc/text_loading_shimmer.dart';
import 'package:fluffychat/pangea/choreographer/repo/full_text_translation_repo.dart';
import 'package:fluffychat/pangea/choreographer/repo/full_text_translation_request_model.dart';
import 'package:fluffychat/pangea/choreographer/repo/full_text_translation_response_model.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import '../../../widgets/matrix.dart';
import '../../bot/utils/bot_style.dart';
import '../../common/controllers/pangea_controller.dart';
import 'igc/card_error_widget.dart';

class ITFeedbackCard extends StatefulWidget {
  final FullTextTranslationRequestModel req;
  final String choiceFeedback;

  const ITFeedbackCard({
    super.key,
    required this.req,
    required this.choiceFeedback,
  });

  @override
  State<ITFeedbackCard> createState() => ITFeedbackCardController();
}

class ITFeedbackCardController extends State<ITFeedbackCard> {
  final PangeaController controller = MatrixState.pangeaController;

  Object? error;
  bool isLoadingFeedback = false;
  bool isTranslating = false;
  FullTextTranslationResponseModel? res;
  String? translatedFeedback;

  Response get noLanguages => Response("", 405);

  @override
  void initState() {
    if (!mounted) return;
    //any setup?
    super.initState();
    getFeedback();
  }

  Future<void> getFeedback() async {
    setState(() {
      isLoadingFeedback = true;
    });

    final result = await FullTextTranslationRepo.get(
      controller.userController.accessToken,
      widget.req,
    );
    res = result.result;

    if (result.isError) error = result.error;
    if (mounted) {
      setState(() {
        isLoadingFeedback = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => error == null
      ? ITFeedbackCardView(controller: this)
      : CardErrorWidget(
          error: L10n.of(context).errorFetchingDefinition,
        );
}

class ITFeedbackCardView extends StatelessWidget {
  const ITFeedbackCardView({
    super.key,
    required this.controller,
  });

  final ITFeedbackCardController controller;

  @override
  Widget build(BuildContext context) {
    const characterWidth = 10.0;

    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      alignment: Alignment.center,
      child: Wrap(
        alignment: WrapAlignment.center,
        children: [
          Text(
            controller.widget.req.text,
            style: BotStyle.text(context),
          ),
          const SizedBox(width: 10),
          Text(
            "≈",
            style: BotStyle.text(context),
          ),
          const SizedBox(width: 10),
          controller.res?.bestTranslation != null
              ? Text(
                  controller.res!.bestTranslation,
                  style: BotStyle.text(context),
                )
              : TextLoadingShimmer(
                  width: min(
                    140,
                    characterWidth * controller.widget.req.text.length,
                  ),
                ),
        ],
      ),
    );
  }
}
