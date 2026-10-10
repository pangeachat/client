import 'dart:async';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/journey_checklist/journey_checklist_extension.dart';
import 'package:fluffychat/features/journey_checklist/journey_step_enum.dart';
import 'package:fluffychat/pangea/common/utils/firebase_analytics.dart';

/// The product moments that advance the journey checklist. Each sends its GA
/// mirror and records its step in one call, so first-party state and
/// measurement cannot drift (google-analytics.instructions.md, one writer per
/// product moment). Recording runs in the background; it never blocks the UI.
abstract class JourneyMoments {
  static void practiceCompleted(Client client, ConstructTypeEnum type) {
    GoogleAnalytics.completePractice(type.canonicalTokenParam);
    unawaited(client.recordJourneyStep(JourneyStep.completePractice));
  }

  /// Called when the subscription page or its discount page appears. Its GA
  /// mirror is that page's screen view, which `WorkspaceScreenTracker` sends.
  /// Recorded from the page, not the tracker: the tracker runs from app
  /// launch, before there is a signed-in client to record for.
  static void subscriptionPageViewed(Client client) =>
      unawaited(client.recordJourneyStep(JourneyStep.viewSubscriptionPage));

  static void translationAccepted(Client client) =>
      unawaited(client.recordJourneyStep(JourneyStep.acceptTranslation));

  static void trialPageClosed(Client client) =>
      unawaited(client.recordJourneyStep(JourneyStep.closeTrialPage));
}
