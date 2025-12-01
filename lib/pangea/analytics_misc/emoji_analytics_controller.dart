import 'package:fluffychat/pangea/analytics_misc/construct_use_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
import 'package:fluffychat/pangea/analytics_misc/put_analytics_controller.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/widgets/matrix.dart';

class EmojiAnalyticsController {
  void sendEmojiAnalytics(
    ConstructIdentifier constructId,
    String? eventId,
    String? roomId,
    String? targetId,
  ) {
    MatrixState.pangeaController.putAnalytics.setState(
      AnalyticsStream(
        eventId: eventId,
        roomId: roomId,
        targetID: targetId,
        constructs: [
          OneConstructUse(
            useType: ConstructUseTypeEnum.em,
            lemma: constructId.lemma,
            constructType: constructId.type,
            metadata: ConstructUseMetaData(
              roomId: roomId,
              timeStamp: DateTime.now(),
              eventId: eventId,
            ),
            category: constructId.category,
            form: constructId.lemma,
            xp: ConstructUseTypeEnum.em.pointValue,
          ),
        ],
      ),
    );
  }
}
