import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/calls/call_ringing_ask.dart';

/// client#9411: a phone with notifications off was asked for full-screen
/// calls, which cannot ring while notifications are off.
void main() {
  CallRingingAsk next({
    bool notificationsOn = false,
    bool askedForNotifications = false,
    bool missedRingForNotifications = false,
    bool fullScreenWanted = false,
  }) => CallRingingAsk.next(
    notificationsOn: notificationsOn,
    askedForNotifications: askedForNotifications,
    missedRingForNotifications: missedRingForNotifications,
    fullScreenWanted: fullScreenWanted,
  );

  test('notifications off asks for them up front', () {
    expect(next(), CallRingingAsk.notifications);
  });

  test('the up-front ask is made once', () {
    expect(next(askedForNotifications: true), CallRingingAsk.none);
  });

  test('a ring kept silent by notifications asks once more', () {
    expect(
      next(askedForNotifications: true, missedRingForNotifications: true),
      CallRingingAsk.notificationsAfterMissedRing,
    );
  });

  test('notifications off never asks for full screen', () {
    expect(
      next(askedForNotifications: true, fullScreenWanted: true),
      CallRingingAsk.none,
    );
    expect(next(fullScreenWanted: true), CallRingingAsk.notifications);
  });

  test('notifications on asks for full screen after a heads-up ring', () {
    expect(
      next(notificationsOn: true, fullScreenWanted: true),
      CallRingingAsk.fullScreen,
    );
  });

  test('notifications on with nothing missed asks nothing', () {
    expect(next(notificationsOn: true), CallRingingAsk.none);
  });
}
