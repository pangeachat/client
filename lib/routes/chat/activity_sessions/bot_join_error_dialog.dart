import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/bot/utils/bot_name.dart';
import 'package:fluffychat/pangea/bot/widgets/bot_face_svg.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';

class PlayWithBotLoadingDialog extends StatefulWidget {
  final Room room;
  const PlayWithBotLoadingDialog({super.key, required this.room});

  @override
  PlayWithBotLoadingDialogState createState() =>
      PlayWithBotLoadingDialogState();
}

class PlayWithBotLoadingDialogState extends State<PlayWithBotLoadingDialog> {
  bool timeout = false;
  Object? error;

  @override
  void initState() {
    super.initState();
    _execute();
  }

  Future<void> _execute() async {
    final future = widget.room.client.onRoomState.stream
        .where(
          (state) =>
              state.roomId == widget.room.id &&
              state.state.type == PangeaEventTypes.activityRole &&
              state.state.senderId == BotName.byEnvironment,
        )
        .first;

    try {
      widget.room.invite(BotName.byEnvironment);
      await future.timeout(const Duration(seconds: 5));
      Navigator.of(context).pop();
    } catch (e, s) {
      if (e is TimeoutException) {
        ErrorHandler.logError(e: e, s: s, data: {}, level: SentryLevel.warning);
        if (mounted) setState(() => timeout = true);
      } else {
        ErrorHandler.logError(e: e, s: s, data: {});
        if (mounted) setState(() => error = e);
      }
    }

    if (timeout) {
      await future;
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool showErrorMessage = error != null || timeout;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: Container(
        width: 300.0,
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BotFace(
              width: 100,
              expression: showErrorMessage
                  ? BotExpression.addled
                  : BotExpression.gold,
            ),
            const SizedBox(height: 8),
            Text(
              showErrorMessage
                  ? L10n.of(context).botActivityJoinFailMessage
                  : L10n.of(context).waitingForBotToJoinActivity,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 40.0,
              child: Center(
                child: showErrorMessage
                    ? TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        child: Text(L10n.of(context).close),
                      )
                    : LinearProgressIndicator(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
