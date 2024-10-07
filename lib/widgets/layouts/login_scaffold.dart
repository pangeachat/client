import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:url_launcher/url_launcher_string.dart';

class LoginScaffold extends StatelessWidget {
  final Widget body;
  final AppBar? appBar;
  final bool enforceMobileMode;

  const LoginScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.enforceMobileMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final isMobileMode =
        enforceMobileMode || !FluffyThemes.isColumnMode(context);
    final scaffold = Scaffold(
      key: const Key('LoginScaffold'),
      // Pangea#
      // appBar: appBar == null
      //     ? null
      //     : AppBar(
      appBar: AppBar(
        // Pangea#
        titleSpacing: appBar?.titleSpacing,
        automaticallyImplyLeading: appBar?.automaticallyImplyLeading ?? true,
        centerTitle: appBar?.centerTitle,
        title: appBar?.title,
        leading: appBar?.leading,
        actions: appBar?.actions,
        // #Pangea
        // backgroundColor: isMobileMode ? null : Colors.transparent,
        backgroundColor: Colors.transparent,
        // Pangea#
      ),
      // #Pangea
      extendBodyBehindAppBar: true,
      // body: body,
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            fit: BoxFit.cover,
            image: AssetImage('assets/login_wallpaper.png'),
          ),
        ),
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: body,
        ),
      ),
      // backgroundColor:
      //     isMobileMode ? null : theme.colorScheme.surface.withOpacity(0.8),
      // bottomNavigationBar: isMobileMode
      //     ? Material(
      //         elevation: 4,
      //         shadowColor: theme.colorScheme.onSurface,
      //         child: const _PrivacyButtons(
      //           mainAxisAlignment: MainAxisAlignment.center,
      //         ),
      //       )
      //     : null,
      // Pangea#
    );
    // #Pangea
    return scaffold;
    // if (isMobileMode) return scaffold;
    // return Container(
    //   decoration: const BoxDecoration(
    //     image: DecorationImage(
    //       fit: BoxFit.cover,
    //       image: AssetImage('assets/login_wallpaper.png'),
    //     ),
    //   ),
    //   child: Column(
    //     children: [
    //       const SizedBox(height: 16),
    //       Expanded(
    //         child: Center(
    //           child: Padding(
    //             padding: const EdgeInsets.symmetric(horizontal: 16.0),
    //             child: Material(
    //               color: Colors.transparent,
    //               borderRadius: BorderRadius.circular(AppConfig.borderRadius),
    //               clipBehavior: Clip.hardEdge,
    //               elevation: theme.appBarTheme.scrolledUnderElevation ?? 4,
    //               shadowColor: theme.appBarTheme.shadowColor,
    //               child: ConstrainedBox(
    //                 constraints: isMobileMode
    //                     ? const BoxConstraints()
    //                     : const BoxConstraints(maxWidth: 480, maxHeight: 640),
    //                 child: BackdropFilter(
    //                   filter: ImageFilter.blur(
    //                     sigmaX: 10.0,
    //                     sigmaY: 10.0,
    //                   ),
    //                   child: scaffold,
    //                 ),
    //               ),
    //             ),
    //           ),
    //         ),
    //       ),
    //       const _PrivacyButtons(mainAxisAlignment: MainAxisAlignment.center),
    //     ],
    //   ),
    // );
    // Pangea#
  }
}

class _PrivacyButtons extends StatelessWidget {
  final MainAxisAlignment mainAxisAlignment;
  const _PrivacyButtons({required this.mainAxisAlignment});

  @override
  Widget build(BuildContext context) {
    final shadowTextStyle = FluffyThemes.isColumnMode(context)
        ? const TextStyle(
            color: Colors.white,
            shadows: [
              Shadow(
                offset: Offset(0.0, 0.0),
                blurRadius: 3,
                color: Colors.black,
              ),
            ],
          )
        : null;
    return SizedBox(
      height: 64,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          mainAxisAlignment: mainAxisAlignment,
          children: [
            TextButton(
              onPressed: () => PlatformInfos.showDialog(context),
              child: Text(
                L10n.of(context)!.about,
                style: shadowTextStyle,
              ),
            ),
            TextButton(
              onPressed: () => launchUrlString(AppConfig.privacyUrl),
              child: Text(
                L10n.of(context)!.privacy,
                style: shadowTextStyle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
