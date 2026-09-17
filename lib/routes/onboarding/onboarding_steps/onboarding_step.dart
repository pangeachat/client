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

  static const double defaultContentMaxWidth = 600.0;

  double get contentMaxWidth => defaultContentMaxWidth;

  String get stepDestination => PRoutes.chatsList;

  /// The joined-course space id onboarding lands on when it ends, or null when
  /// no course was joined — then the plain path ([stepDestination]) is used.
  /// The token destination needs the current workspace URI to build (a course
  /// opens via `WorkspaceNav.openCourseSection`, not a path literal), which
  /// only the call site (`OnboardingController`, with a `BuildContext`) has —
  /// so the step exposes the space id and the caller builds the location,
  /// rather than pushing a `Uri` parameter through every step.
  ///
  /// It reads the shared onboarding state rather than being answered per step,
  /// because the controller asks whichever step ENDED the flow, and that isn't
  /// always the joined-course page: a new user is inside the trial window, so
  /// the trial page follows it, and answering null there landed a learner who
  /// had just joined a course on the chat list (#8593). Any flow that joined a
  /// course lands on that course, whatever step it ends on. See
  /// `routing.instructions.md`.
  String? get joinedCourseSpaceId => state.joinedRoomId;

  String nextStepText(L10n l10n) => l10n.next;

  String lastStepText(L10n l10n) => l10n.letsGo;

  Future<OnboardingStep?> execute();

  OnboardingStep? skip();
}
