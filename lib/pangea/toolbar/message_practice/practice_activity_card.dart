import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/common/widgets/card_error_widget.dart';
import 'package:fluffychat/pangea/common/widgets/content_loading_indicator.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';
import 'package:fluffychat/pangea/practice_activities/practice_target.dart';
import 'package:fluffychat/pangea/toolbar/message_practice/message_morph_choice.dart';
import 'package:fluffychat/pangea/toolbar/message_practice/practice_controller.dart';
import 'package:fluffychat/pangea/toolbar/message_practice/practice_match_card.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The wrapper for practice activity content.
/// Handles the activities associated with a message,
/// their navigation, and the management of completion records
class PracticeActivityCard extends StatefulWidget {
  final PracticeTarget targetTokensAndActivityType;
  final PracticeController controller;
  final PangeaToken? selectedToken;
  final double maxWidth;

  const PracticeActivityCard({
    super.key,
    required this.targetTokensAndActivityType,
    required this.controller,
    required this.selectedToken,
    required this.maxWidth,
  });

  @override
  PracticeActivityCardState createState() => PracticeActivityCardState();
}

class PracticeActivityCardState extends State<PracticeActivityCard> {
  final ValueNotifier<AsyncState<PracticeActivityModel>> _activityState =
      ValueNotifier(const AsyncState.loading());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _fetchActivity(),
    );
  }

  @override
  void didUpdateWidget(PracticeActivityCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetTokensAndActivityType !=
        widget.targetTokensAndActivityType) {
      _fetchActivity();
    }
  }

  @override
  void dispose() {
    _activityState.dispose();
    super.dispose();
  }

  Future<void> _fetchActivity() async {
    _activityState.value = const AsyncState.loading();
    if (!MatrixState.pangeaController.userController.languagesSet) {
      _activityState.value = const AsyncState.error("Error fetching activity");
      return;
    }

    final result = await widget.controller.fetchActivityModel(
      widget.targetTokensAndActivityType,
    );

    if (result.isValue) {
      _activityState.value = AsyncState.loaded(result.result!);
    } else {
      _activityState.value = AsyncState.error(
        "Error fetching activity: ${result.asError}",
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: _activityState,
      builder: (context, state, __) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            switch (state) {
              AsyncLoading() => const ContentLoadingIndicator(
                  height: 40,
                ),
              AsyncError() => CardErrorWidget(
                  L10n.of(context).errorFetchingActivity,
                ),
              AsyncLoaded() => state.value.multipleChoiceContent != null
                  ? MessageMorphInputBarContent(
                      controller: widget.controller,
                      activity: state.value,
                      selectedToken: widget.selectedToken,
                      maxWidth: widget.maxWidth,
                    )
                  : MatchActivityCard(
                      currentActivity: state.value,
                      controller: widget.controller,
                    ),
              _ => const SizedBox.shrink(),
            },
          ],
        );
      },
    );
  }
}
