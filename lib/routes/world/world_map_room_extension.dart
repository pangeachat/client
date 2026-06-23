import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/routes/world/world_map_large_card.dart';

extension WorldMapRoomExtension on Room {
  List<LargeCardParticipant> get largeCardParticipants => getParticipants()
      .where(
        (u) => u.membership == Membership.join && u.id != BotName.byEnvironment,
      )
      .map<LargeCardParticipant>(
        (u) => (avatar: u.avatarUrl, name: u.calcDisplayname()),
      )
      .toList();
}
