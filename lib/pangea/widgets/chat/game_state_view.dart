import 'dart:async';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pangea/constants/game_constants.dart';
import 'package:fluffychat/pangea/constants/model_keys.dart';
import 'package:fluffychat/pangea/constants/pangea_event_types.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension/pangea_room_extension.dart';
import 'package:fluffychat/pangea/models/games/game_state_model.dart';
import 'package:fluffychat/pangea/utils/bot_name.dart';
import 'package:fluffychat/pangea/utils/bot_style.dart';
import 'package:fluffychat/pangea/utils/error_handler.dart';
import 'package:fluffychat/pangea/widgets/chat/round_timer.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:matrix/matrix.dart';

class GameStateView extends StatefulWidget {
  final Room room;
  const GameStateView(this.room, {super.key});

  @override
  GameStateViewState createState() => GameStateViewState();
}

class GameStateViewState extends State<GameStateView> {
  final int roundDelaySeconds = 5;
  Timer? timer;
  StreamSubscription? stateSubscription;
  DateTime? waitBeginTime;

  GameModel get gameState => room.gameState;
  Room get room => widget.room;

  int? get currentSeconds {
    if (room.isActiveRound) {
      return room.currentRoundDuration?.inSeconds;
    }
    if (room.isBetweenRounds) {
      return room.roundWaitDuration(waitBeginTime)?.inSeconds;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();

    onGameStateUpdate(animate: false);

    stateSubscription = Matrix.of(context)
        .client
        .onRoomState
        .stream
        .where(isRoundUpdate)
        .listen((_) => onGameStateUpdate());
  }

  bool isRoundUpdate(update) {
    return update.roomId == room.id &&
        update.state is Event &&
        (update.state as Event).type == PangeaEventTypes.storyGame;
  }

  void onGameStateUpdate({bool animate = true}) {
    setState(() {});
    if (gameState.phase == StoryGamePhase.beginWaitNextRound) {
      waitBeginTime = DateTime.now();
    }
    if (room.isActiveRound || room.isBetweenRounds) {
      timer?.cancel();
      timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
        if ((currentSeconds ?? 0) >= GameConstants.timerMaxSeconds) {
          t.cancel();
        }
        setState(() {});
      });
    }
  }

  @override
  void dispose() {
    super.dispose();

    stateSubscription?.cancel();
    stateSubscription = null;

    timer?.cancel();
    timer = null;
  }

  String? get blockText {
    if (room.isActiveRound) {
      if (gameState.currentCharacter == null) {
        ErrorHandler.logError(e: "currentCharacter is null in active round");
        return null;
      }
      return gameState.currentCharacter! != ModelKey.narrator
          ? L10n.of(context)!.currentCharDialoguePrompt(
              gameState.currentCharacter!,
            )
          : L10n.of(context)!.narrationPrompt;
    }
    return room.gameState.phase?.string(context);
  }

  String? get avatarName =>
      room.isActiveRound && gameState.currentCharacter != ModelKey.narrator
          ? gameState.currentCharacter
          : null;

  // User? get judge => room.getParticipants().firstWhereOrNull(
  //       (user) => user.id == gameState.judge,
  //     );

  List<User> get players => room
      .getParticipants()
      .where(
        (user) => user.id != BotName.byEnvironment,
        // && user.id != gameState.judge,
      )
      .toList();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.all(Radius.circular(4)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    AnimatedSize(
                      duration: FluffyThemes.animationDuration,
                      child: avatarName == null
                          ? const SizedBox.shrink()
                          : Avatar(name: avatarName),
                    ),
                    const SizedBox(width: 8),
                    blockText != null
                        ? Text(
                            blockText!,
                            textAlign: TextAlign.center,
                            style: BotStyle.text(context, big: true),
                          )
                        : const Center(
                            child: CircularProgressIndicator.adaptive(),
                          ),
                  ],
                ),
              ),
              RoundTimer(
                currentSeconds ?? 0,
                maxSeconds: room.isBetweenRounds
                    ? gameState.delayBeforeNextRoundSeconds
                    : GameConstants.timerMaxSeconds,
                color: room.isBetweenRounds ? Colors.green : null,
              ),
            ],
          ),
          if (room.isActiveRound &&
              // gameState.judge != null &&
              players.isNotEmpty)
            // Row(
            //   crossAxisAlignment: CrossAxisAlignment.center,
            //   children: [
            //     Text(
            //       L10n.of(context)!.judgeThisRound,
            //       style: BotStyle.text(context),
            //     ),
            //     Padding(
            //       padding: const EdgeInsets.all(2),
            //       child: Tooltip(
            //         message: judge?.calcDisplayname() ?? gameState.judge,
            //         child: Avatar(
            //           mxContent: judge?.avatarUrl,
            //           name: judge?.calcDisplayname() ?? gameState.judge,
            //           size: 24,
            //           onTap: () {},
            //         ),
            //       ),
            //     ),
            //     const SizedBox(width: 16),
            //     Text(
            //       L10n.of(context)!.playersThisRound,
            //       style: BotStyle.text(context),
            //     ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: players
                  .map(
                    (user) => Padding(
                      padding: const EdgeInsets.all(2),
                      child: Tooltip(
                        message: user.calcDisplayname(),
                        child: AnimatedOpacity(
                          duration: FluffyThemes.animationDuration,
                          opacity:
                              room.userHasVotedThisRound(user.id) ? 1 : 0.25,
                          child: Avatar(
                            mxContent: user.avatarUrl,
                            name: user.calcDisplayname(),
                            size: 24,
                            onTap: () {},
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          //   ],
          // ),
          // ],
        ],
      ),
    );
  }
}
