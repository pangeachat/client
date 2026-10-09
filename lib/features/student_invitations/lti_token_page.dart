import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/features/student_invitations/lti_entry.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/home/login_loading_dialog.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// `/lti/token` — signs a linked Canvas learner in with the module's
/// single-use login token (C5: standard `m.login.token`, about two minutes),
/// the token already out of the address bar (LtiEntry.tokenRedirect). The
/// token is taken once; a reload finds none and offers the normal login.
/// The route is a sign-in entry (PAuthGaurd.isEntryLocation), so the login
/// listener moves a finished login on to the app. Already signed in: the
/// token is left to expire and the app opens.
class LtiTokenPage extends StatefulWidget {
  const LtiTokenPage({super.key});

  @override
  State<LtiTokenPage> createState() => _LtiTokenPageState();
}

class _LtiTokenPageState extends State<LtiTokenPage> {
  bool _nothingToFinish = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _signIn());
  }

  Future<void> _signIn() async {
    if (!mounted) return;
    final token = LtiEntry.takeLoginToken();
    final matrix = Matrix.of(context);
    if (matrix.client.isLogged()) {
      context.go(PRoutes.world);
      return;
    }
    if (token == null) {
      setState(() => _nothingToFinish = true);
      return;
    }
    final client = await matrix.getLoginClient();
    if (!mounted) return;
    await showAdaptiveDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => LoginLoadingDialog(
        client: client,
        loginType: LoginType.mLoginToken,
        token: token,
        initialDeviceDisplayName: PlatformInfos.clientName,
      ),
    );
    // A failed sign-in was shown in the dialog; the token is spent.
    if (mounted && !client.isLogged()) {
      setState(() => _nothingToFinish = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: _nothingToFinish
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 16.0,
                    children: [
                      Text(
                        l10n.canvasSignInExpired,
                        textAlign: TextAlign.center,
                      ),
                      ElevatedButton(
                        onPressed: () => context.go('/home/login'),
                        child: Text(l10n.login),
                      ),
                    ],
                  )
                : const CircularProgressIndicator.adaptive(),
          ),
        ),
      ),
    );
  }
}
