import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/notifications/notification_tap_utils.dart';
import 'sentry_capture_harness.dart';

/// The notice content contract (the engagement repo's analytics doc): an open
/// is counted by its variant, and the product action rides along only when the
/// notice's goal names one. Notices whose goal has no product action used to be
/// dropped from GA entirely, because the open required a target_event_name.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SentryCaptureHarness sentry;

  setUp(() async {
    sentry = SentryCaptureHarness();
    await sentry.init();
  });

  tearDown(() => sentry.close());

  Map<String, String>? parametersFor(Map<String, dynamic> notification) =>
      NotificationTapUtil.botNotificationOpenedParameters(notification);

  test('a notice with only a variant is logged by its variant', () async {
    await sentry.expectNoReport(() {
      expect(
        parametersFor({
          'content_pangea.analytics.variant': 'continue_activity',
          'content_check_in_type': 'continue_activity',
          'content_pangea.analytics.target_param.room_id': '!s:example.com',
        }),
        {
          'variant': 'continue_activity',
          'notification_type': 'continue_activity',
          'room_id': '!s:example.com',
        },
      );
    });
  });

  test('a goal\'s product action rides along with the variant', () async {
    await sentry.expectNoReport(() {
      expect(
        parametersFor({
          'content_pangea.analytics.variant': 'try_activity',
          'content_pangea.analytics.target_event_name': 'start_activity',
        }),
        {'target_event_name': 'start_activity', 'variant': 'try_activity'},
      );
    });
  });

  test('a product action alone is still logged, as before', () async {
    await sentry.expectNoReport(() {
      expect(
        parametersFor({
          'content_pangea.analytics.target_event_name': 'sent_message',
        }),
        {'target_event_name': 'sent_message'},
      );
    });
  });

  test(
    'an unknown product action is reported and left off, not the open',
    () async {
      late Map<String, String>? parameters;
      final event = await sentry.capture(() {
        parameters = parametersFor({
          'content_pangea.analytics.variant': 'join_course',
          'content_pangea.analytics.target_event_name': 'not_an_action',
        });
      });
      expect(parameters, {'variant': 'join_course'});
      expect(
        event.throwable.toString(),
        contains('Unknown BotTargetEventName: not_an_action'),
      );
    },
  );

  test('a notice with neither is not logged', () async {
    await sentry.expectNoReport(() {
      expect(
        parametersFor({
          'content_check_in_type': 'default',
          'content_pangea.analytics.variant': '',
          'content_pangea.analytics.target_param.chat_id': 7,
        }),
        isNull,
      );
    });
  });
}
