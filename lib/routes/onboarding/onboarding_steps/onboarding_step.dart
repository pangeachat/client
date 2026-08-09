import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/onboarding/onboarding_state_controller.dart';

abstract class OnboardingStep {
  final Client client;
  final OnboardingStateController state;
  final int maxRemainingSteps;

  const OnboardingStep({
    required this.client,
    required this.state,
    required this.maxRemainingSteps,
  });

  bool get enableGoForward => true;

  bool get customView => false;

  String get stepDestination => PRoutes.chatsList;

  /// The joined-course space id this step should land on, or null for every
  /// step whose destination is a plain path ([stepDestination]). The token
  /// destination needs the current workspace URI to build (a course opens via
  /// `WorkspaceNav.openCourseSection`, not a path literal), which only the
  /// call site (`OnboardingController`, with a `BuildContext`) has — so the
  /// step exposes the space id and the caller builds the location, rather
  /// than pushing a `Uri` parameter through every step. See
  /// `routing.instructions.md`.
  String? get joinedCourseSpaceId => null;

  String nextStepText(L10n l10n) => l10n.next;

  String lastStepText(L10n l10n) => l10n.letsGo;

  Future<OnboardingStep?> execute();

  OnboardingStep? skip();
}
