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

  const ClientTrialInfoProvider({
    required this.client,
    required this.inTrialWindow,
    required this.hasSeat,
  });

  /// A seat holder already has access, so the free-trial offer is skipped.
  @override
  bool get shouldShowTrialPage =>
      inTrialWindow && !client.showedTrialPage && !hasSeat();

  @override
  Future<void> setShowedTrialPage() => client.setShowedTrialPage();
}

class MockTrialInfoProvider implements TrialInfoProvider {
  @override
  bool get shouldShowTrialPage => false;

  @override
  Future<void> setShowedTrialPage() async {}
}
