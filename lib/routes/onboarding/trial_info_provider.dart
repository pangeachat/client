import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/onboarding/onboarding_client_extension.dart';

abstract class TrialInfoProvider {
  bool get shouldShowTrialPage;

  Future<void> setShowedTrialPage();
}

class ClientTrialInfoProvider implements TrialInfoProvider {
  final Client client;
  final bool inTrialWindow;

  const ClientTrialInfoProvider({
    required this.client,
    required this.inTrialWindow,
  });

  @override
  bool get shouldShowTrialPage => inTrialWindow && !client.showedTrialPage;

  @override
  Future<void> setShowedTrialPage() => client.setShowedTrialPage();
}

class MockTrialInfoProvider implements TrialInfoProvider {
  @override
  bool get shouldShowTrialPage => false;

  @override
  Future<void> setShowedTrialPage() async {}
}
