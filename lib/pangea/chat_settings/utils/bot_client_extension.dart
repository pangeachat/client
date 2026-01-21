import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/bot/utils/bot_name.dart';
import 'package:fluffychat/pangea/bot/utils/bot_room_extension.dart';
import 'package:fluffychat/pangea/chat/constants/default_power_level.dart';
import 'package:fluffychat/pangea/chat_settings/constants/bot_mode.dart';
import 'package:fluffychat/pangea/chat_settings/models/bot_options_model.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';
import 'package:fluffychat/pangea/user/user_model.dart';
import 'package:fluffychat/widgets/matrix.dart';

extension BotClientExtension on Client {
  bool get hasBotDM => rooms.any((r) => r.isBotDM);
  Room? get botDM => rooms.firstWhereOrNull((r) => r.isBotDM);

  // All 2-member rooms with the bot
  List<Room> get targetBotChats => rooms.where((r) {
        if (r.isBotDM) return true;
        if (r.summary.mJoinedMemberCount != 2) return false;
        return r.getParticipants().any((u) => u.id == BotName.byEnvironment);
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
    final rooms = targetBotChats;
    if (rooms.isEmpty) return;

    final futures = <Future>[];
    for (final room in rooms) {
      final botOptions = room.botOptions ?? const BotOptionsModel();
      final targetLanguage = userSettings.targetLanguage;
      final languageLevel = userSettings.cefrLevel;
      final voice = userSettings.voice;

      if (botOptions.targetLanguage == targetLanguage &&
          botOptions.languageLevel == languageLevel &&
          botOptions.targetVoice == voice) {
        continue;
      }

      final updated = botOptions.copyWith(
        targetLanguage: targetLanguage,
        languageLevel: languageLevel,
        targetVoice: voice,
      );
      futures.add(room.setBotOptions(updated));
    }

    await Future.wait(futures);
  }
}
