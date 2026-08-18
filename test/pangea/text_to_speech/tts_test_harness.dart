import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:fluffychat/features/dosage/dosage_audio_category.dart';
import 'package:fluffychat/features/dosage/dosage_tts_listening_probe.dart';
import 'package:fluffychat/features/subscription/controllers/subscription_controller.dart';
import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/routes/settings/settings_learning/tool_settings_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// A probe that records what `tryToSpeak` did to it.
///
/// The measurement's bracketing moved OUT of the call sites and INTO
/// `tryToSpeak` (#104), so "the caller remembered to close it" stopped being a
/// per-site property and became one guarantee to pin. This counts the three
/// transitions so the guarantee is asserted rather than assumed.
class SpyProbe extends DosageTtsListeningProbe {
  SpyProbe({
    super.buffer,
    super.now,
    super.category = DosageListeningCategory.autoRead,
    // Defaults to a real room; the roomless surfaces pass null explicitly,
    // which is the whole point of the argument being nullable AND required.
    super.roomId = '!room:example.org',
  }) : super(
         userId: () => '@learner:example.org',
         accessToken: () => 'syt_token',
       );

  int starts = 0;
  int aborts = 0;
  int finishes = 0;

  @override
  void started() {
    starts++;
    super.started();
  }

  @override
  void aborted() {
    aborts++;
    super.aborted();
  }

  @override
  void finish() {
    finishes++;
    super.finish();
  }
}

/// A controller complete enough for playback to actually REACH a route,
/// rather than throwing in setup like `FakePangeaController` does.
///
/// Three things stand between `tryToSpeak` and a route that plays, and all
/// three read off the controller: the shared audio player it stops first, the
/// per-surface tool setting that gates the use case, and the subscription flag
/// the routing decision reads. A test that stops short of the route can only
/// ever assert what happens when nothing plays.
///
/// Unsubscribed by default: the device route is the one reachable without a
/// network, and staying off the paid route is what keeps a test hermetic. Pass
/// [subscribed] (and run under an `http.runWithClient` MockClient) to let the
/// backend route be reached.
class PlayablePangeaController implements PangeaController {
  PlayablePangeaController({bool subscribed = false})
    : subscriptionController = _SubscriptionFlag(subscribed);

  @override
  final UserController userController = _EnabledUserController();

  @override
  final SubscriptionController subscriptionController;

  @override
  MatrixState get matrixState => _NoPlayerMatrixState();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _EnabledUserController implements UserController {
  @override
  bool isToolEnabled(ToolSetting setting) => true;

  @override
  String? get userL1Code => 'en';

  /// A token, so a backend request gets past `BaseRepo` and reaches whatever
  /// `http.Client` the test installed.
  @override
  String get accessToken => 'test-token';

  @override
  Completer<void> initCompleter = Completer<void>();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _SubscriptionFlag implements SubscriptionController {
  _SubscriptionFlag(this._subscribed);
  final bool _subscribed;

  @override
  bool get showSubscriptionGatedContent => _subscribed;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A shared audio player that is simply absent, which is what `tryToSpeak`
/// stopping it before every request has to tolerate.
class _NoPlayerMatrixState implements MatrixState {
  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) =>
      '_NoPlayerMatrixState';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
