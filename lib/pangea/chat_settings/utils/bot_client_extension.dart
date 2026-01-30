import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/pangea/bot/utils/bot_name.dart';
import 'package:fluffychat/pangea/bot/utils/bot_room_extension.dart';
import 'package:fluffychat/pangea/chat/constants/default_power_level.dart';
import 'package:fluffychat/pangea/chat_settings/constants/bot_mode.dart';
import 'package:fluffychat/pangea/chat_settings/models/bot_options_model.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';
import 'package:fluffychat/pangea/user/user_model.dart';
import 'package:fluffychat/widgets/matrix.dart';

extension BotClientExtension on Client {
  bool get hasBotDM => rooms.any((r) => r.isBotDM);
  Room? get botDM => rooms.firstWhereOrNull((r) => r.isBotDM);

  // All 2-member rooms with the bot
  List<Room> get _targetBotChats => rooms.where((r) {
        return
            // bot settings exist
            r.botOptions != null &&
                // there is no activity plan
                r.activityPlan == null &&
                // it's just the bot and one other user in the room
                r.summary.mJoinedMemberCount == 2 &&
                r.getParticipants().any((u) => u.id == BotName.byEnvironment);
      }).toList();

  Future<String> startChatWithBot() => startDirectChat(
        BotName.byEnvironment,
        preset: CreateRoomPreset.trustedPrivateChat,
        initialState: [
          StateEvent(
            content: BotOptionsModel(
              mode: BotMode.directChat,
              targetLanguage:
                  MatrixState.pangeaController.userController.userL2?.langCode,
              languageLevel: MatrixState.pangeaController.userController.profile
                  .userSettings.cefrLevel,
            ).toJson(),
            type: PangeaEventTypes.botOptions,
          ),
          RoomDefaults.defaultPowerLevels(
            userID!,
          ),
        ],
      );

  Future<void> updateBotOptions(UserSettings userSettings) async {
    final targetBotRooms = [..._targetBotChats];
    if (targetBotRooms.isEmpty) return;

    try {
      final futures = <Future>[];
      for (final targetBotRoom in targetBotRooms) {
        final botOptions = targetBotRoom.botOptions ?? const BotOptionsModel();
        final targetLanguage = userSettings.targetLanguage;
        final languageLevel = userSettings.cefrLevel;
        final voice = userSettings.voice;
        final gender = userSettings.gender;

        if (botOptions.targetLanguage == targetLanguage &&
            botOptions.languageLevel == languageLevel &&
            botOptions.targetVoice == voice &&
            botOptions.targetGender == gender) {
          continue;
        }

        final updated = botOptions.copyWith(
          targetLanguage: targetLanguage,
          languageLevel: languageLevel,
          targetVoice: voice,
          targetGender: gender,
        );
        futures.add(targetBotRoom.setBotOptions(updated));
      }

      await Future.wait(futures);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          'userSettings': userSettings.toJson(),
          'targetBotRooms': targetBotRooms.map((r) => r.id).toList(),
        },
      );
    }
  }
}
