import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/onboarding/onboarding.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_complete.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_constants.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps_enum.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/widgets/layouts/empty_page.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

class OnboardingView extends StatelessWidget {
  final OnboardingController controller;

  const OnboardingView({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    final isColumnMode = FluffyThemes.isColumnMode(context);

    if (OnboardingController.isClosed && isColumnMode) {
      return const EmptyPage();
    }

    final screenheight = MediaQuery.of(context).size.height;
    final screenwidth = MediaQuery.of(context).size.width;

    return Material(
      child: StreamBuilder(
        key: ValueKey(
          client.userID.toString(),
        ),
        stream: client.onSync.stream
            .where((s) => s.hasRoomUpdate)
            .rateLimit(const Duration(seconds: 1)),
        builder: (context, _) {
          return Stack(
            alignment: Alignment.topCenter,
            children: [
              if (!OnboardingController.isClosed)
                Positioned(
                  bottom: 0.0,
                  child: AnimatedOpacity(
                    duration: FluffyThemes.animationDuration,
                    opacity: OnboardingController.isComplete ? 1.0 : 0.3,
                    child: CachedNetworkImage(
                      imageUrl:
                          "${AppConfig.assetsBaseURL}/${OnboardingConstants.onboardingImageFileName}",
                      fit: BoxFit.fitWidth,
                    ),
                  ),
                ),
              Divider(
                color: isColumnMode
                    ? Colors.transparent
                    : Theme.of(context).colorScheme.primary,
                thickness: 2.0,
                indent: 20.0,
                height: 20.0,
                endIndent: 20.0,
                radius: BorderRadius.circular(2),
              ),
              AnimatedContainer(
                duration: FluffyThemes.animationDuration,
                constraints: const BoxConstraints(minWidth: 0, maxWidth: 850.0),
                height: OnboardingController.isClosed ? 0 : screenheight,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: 42.0,
                    horizontal: isColumnMode ? 20.0 : 5.0,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(context).colorScheme.surface,
                          Theme.of(context)
                              .colorScheme
                              .surface
                              .withValues(alpha: 0),
                        ],
                        stops: const [0.75, 0.95],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: MaxWidthBody(
                      showBorder: true,
                      maxWidth: 850.0,
                      child: Column(
                        children: [
                          Text(
                            L10n.of(context).getStarted,
                            style: TextStyle(
                              fontSize: isColumnMode ? 32.0 : 24.0,
                              height: isColumnMode ? 1.2 : 1.5,
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.all(
                              isColumnMode ? 40.0 : 12.0,
                            ),
                            child: Row(
                              spacing: 8.0,
                              mainAxisSize: MainAxisSize.min,
                              children: OnboardingStepsEnum.values.map((step) {
                                final complete =
                                    OnboardingController.complete(step);
                                return CircleAvatar(
                                  radius: 6.0,
                                  backgroundColor: complete
                                      ? AppConfig.success
                                      : Theme.of(context).colorScheme.primary,
                                  child: CircleAvatar(
                                    radius: 3.0,
                                    backgroundColor:
                                        Theme.of(context).colorScheme.surface,
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          OnboardingController.isComplete
                              ? OnboardingComplete(
                                  controller: controller,
                                )
                              : Column(
                                  spacing: 12.0,
                                  children: [
                                    for (final step
                                        in OnboardingStepsEnum.values)
                                      OnboardingStep(
                                        step: step,
                                        isComplete:
                                            OnboardingController.complete(step),
                                        onPressed: () =>
                                            controller.onPressed(step),
                                      ),
                                  ],
                                ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
