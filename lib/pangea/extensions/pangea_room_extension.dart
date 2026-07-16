// ignore_for_file: implementation_imports, depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/foundation.dart';

import 'package:html_unescape/html_unescape.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/markdown.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/analytics/constructs_event.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/features/analytics_data/analytics_events_repo.dart';
import 'package:fluffychat/features/analytics_data/analytics_status_room_extension.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/pangea/spaces/space_constants.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/igc_request_model.dart';
import 'package:fluffychat/routes/chat/events/constants/message_constants.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';
import 'package:fluffychat/routes/chat/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/routes/chat/events/models/tokens_event_content_model.dart';
import '../../routes/chat/choreographer/choreo_record_model.dart';
import '../../routes/chat/events/constants/pangea_event_types.dart';
import '../../routes/chat/events/models/representation_content_model.dart';

part "../../features/analytics/room_analytics_extension.dart";
part "../../routes/chat/chat_details/room_capacity_extension.dart";
part "room_children_and_parents_extension.dart";
part "room_events_extension.dart";
part "room_information_extension.dart";
part "room_user_permissions_extension.dart";

extension PangeaRoom on Room {
  // analytics
}
