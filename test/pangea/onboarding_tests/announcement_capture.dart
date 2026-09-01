import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

/// Collects, in order, the messages `SemanticsService.sendAnnouncement` sends
/// over the accessibility platform channel, so a test can assert what a
/// screen reader would hear. Call before pumping; announcements fired during
/// the pump land in the returned list too.
List<String> captureAnnouncements(WidgetTester tester) {
  final announcements = <String>[];
  tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
    SystemChannels.accessibility,
    (message) async {
      final map = message as Map<Object?, Object?>;
      if (map['type'] == 'announce') {
        final data = map['data'] as Map<Object?, Object?>;
        announcements.add(data['message'] as String);
      }
      return null;
    },
  );
  return announcements;
}
