import 'package:flutter/material.dart';

import 'package:get_storage/get_storage.dart';
import 'package:go_router/go_router.dart';

import 'package:fluffychat/pangea/bot/utils/bot_name.dart';
import 'package:fluffychat/pangea/chat_settings/utils/bot_client_extension.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps_enum.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_view.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class Onboarding extends StatefulWidget {
  const Onboarding({super.key});

  @override
  OnboardingController createState() => OnboardingController();
}

class OnboardingController extends State<Onboarding> {
  static final GetStorage _onboardingStorage = GetStorage('onboarding_storage');

  @override
  void initState() {
    super.initState();
    // Initialize the storage if needed
    GetStorage.init('onboarding_storage').then((_) {
      if (mounted) setState(() {});
    });
  }

  static bool get isClosed => _onboardingStorage.read('closed') ?? false;

  static bool get isComplete => OnboardingStepsEnum.values.every(
        (step) => complete(step),
      );

  static bool complete(OnboardingStepsEnum step) {
    switch (step) {
      case OnboardingStepsEnum.chatWithBot:
        return MatrixState.pangeaController.matrixState.client.hasBotDM;
      case OnboardingStepsEnum.joinSpace:
        return MatrixState.pangeaController.matrixState.client.rooms.any(
          (r) => r.isSpace,
        );
      case OnboardingStepsEnum.inviteFriends:
        return MatrixState.pangeaController.matrixState.client.rooms.any(
          (r) =>
              r.isDirectChat && r.directChatMatrixID != BotName.byEnvironment,
        );
    }
  }

  Future<void> closeCompletedMessage() async {
    await _onboardingStorage.write('closed', true);
    if (mounted) setState(() {});
  }

  Future<void> inviteFriends() async {
    FluffyShare.shareInviteLink(context);
  }

  Future<void> startChatWithBot() async {
    final resp = await showFutureLoadingDialog<String>(
      context: context,
      future: () => Matrix.of(context).client.startChatWithBot(),
    );
    if (resp.isError) return;
    context.go("/rooms/${resp.result}");
  }

  void joinCommunities() {
    context.go('/rooms/communities');
  }

  Future<void> onPressed(OnboardingStepsEnum step) async {
    switch (step) {
      case OnboardingStepsEnum.chatWithBot:
        return startChatWithBot();
      case OnboardingStepsEnum.joinSpace:
        return joinCommunities();
      case OnboardingStepsEnum.inviteFriends:
        return inviteFriends();
    }
  }

  @override
  Widget build(BuildContext context) => OnboardingView(controller: this);
}
