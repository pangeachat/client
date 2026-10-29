import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/onboarding/onboarding_client_extension.dart';

abstract class TrialInfoProvider {
  bool get shouldShowTrialPage;

  Future<void> setShowedTrialPage();
}

class ClientTrialInfoProvider implements TrialInfoProvider {
  final Client client;
  final bool inTrialWindow;

  /// Whether the account already holds a seat, read from the subscription
  /// status the app already loaded. Called when a step is decided, not at
  /// construction: the status may still be loading when onboarding starts.
  final bool Function() hasSeat;

  /// Whether a seat invitation is still unsettled: stored and not yet
  /// opened, or opened and waiting for the teacher's approval. Read when a
  /// step is decided, like [hasSeat].
  final bool Function() invitationWaiting;

  const ClientTrialInfoProvider({
    required this.client,
    required this.inTrialWindow,
    required this.hasSeat,
    required this.invitationWaiting,
  });

  /// A seat holder already has access, and a student whose seat may still
  /// come must not spend the trial meanwhile, so the free-trial offer is
  /// skipped for both.
  @override
  bool get shouldShowTrialPage =>
      inTrialWindow &&
      !client.showedTrialPage &&
      !hasSeat() &&
      !invitationWaiting();

  @override
  Future<void> setShowedTrialPage() => client.setShowedTrialPage();
}

class MockTrialInfoProvider implements TrialInfoProvider {
  @override
  bool get shouldShowTrialPage => false;

  @override
  Future<void> setShowedTrialPage() async {}
}
