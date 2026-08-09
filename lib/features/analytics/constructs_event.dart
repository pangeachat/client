import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics/constructs_model.dart';
import '../../routes/chat/events/constants/pangea_event_types.dart';

class ConstructAnalyticsEvent {
  late Event _event;
  ConstructAnalyticsModel? contentCache;
  ConstructAnalyticsEvent({required Event event}) {
    _event = event;
    if (event.type != PangeaEventTypes.construct) {
      throw Exception(
        "${event.type} should not be used to make a ConstructAnalyticsEvent",
      );
    }
  }

  Event get event => _event;

  ConstructAnalyticsModel get content {
    contentCache ??= ConstructAnalyticsModel.fromJson(event.content);
    return contentCache as ConstructAnalyticsModel;
  }
}
