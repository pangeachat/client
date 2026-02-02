import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/authentication/p_logout.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/login/pages/pangea_login_scaffold.dart';
import 'package:fluffychat/widgets/local_notifications_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';

class EnableNotifications extends StatefulWidget {
  const EnableNotifications({super.key});

  @override
  EnabledNotificationsController createState() =>
      EnabledNotificationsController();
}

class EnabledNotificationsController extends State<EnableNotifications> {
  Profile? profile;

  @override
  void initState() {
    _setProfile();
    super.initState();
  }

  Future<void> _setProfile() async {
    final client = Matrix.of(context).client;
    try {
      profile = await client.getProfileFromUserId(
        client.userID!,
      );
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          'userId': client.userID,
        },
      );
    } finally {
      if (mounted) setState(() {});
    }
  }

  Future<void> _requestNotificationPermission() async {
    await Matrix.of(context).requestNotificationPermission();
    if (mounted) {
      context.push("/registration/course");
    }
  }

  @override
  Widget build(BuildContext context) {
    return PangeaLoginScaffold(
      customAppBar: AppBar(
        title: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 450,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              BackButton(
                onPressed: () => pLogoutAction(
                  context,
                  bypassWarning: true,
                ),
              ),
              const SizedBox(
                width: 40.0,
              ),
            ],
          ),
        ),
        automaticallyImplyLeading: false,
      ),
      showAppName: false,
      mainAssetUrl: profile?.avatarUrl,
      children: [
        Column(
          spacing: 8.0,
          children: [
            Text(
              L10n.of(context).welcomeUser(
                profile?.displayName ??
                    Matrix.of(context).client.userID?.localpart ??
                    "",
              ),
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              L10n.of(context).enableNotificationsTitle,
              textAlign: TextAlign.center,
            ),
            ElevatedButton(
              onPressed: _requestNotificationPermission,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                foregroundColor:
                    Theme.of(context).colorScheme.onPrimaryContainer,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(L10n.of(context).enableNotificationsDesc),
                ],
              ),
            ),
            TextButton(
              child: Text(L10n.of(context).skipForNow),
              onPressed: () => context.push("/registration/course"),
            ),
          ],
        ),
      ],
    );
  }
}
