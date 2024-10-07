import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/pages/connect/p_sso_button.dart';
import 'package:fluffychat/pangea/widgets/common/pangea_logo_svg.dart';
import 'package:fluffychat/pangea/widgets/signup/signup_buttons.dart';
import 'package:fluffychat/widgets/layouts/login_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';

import 'homeserver_picker.dart';

class HomeserverPickerView extends StatelessWidget {
  final HomeserverPickerController controller;

  const HomeserverPickerView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LoginScaffold(
      // #Pangea
      // enforceMobileMode: Matrix.of(context).client.isLogged(),
      // appBar: controller.widget.addMultiAccount
      //     ? AppBar(
      //         centerTitle: true,
      //         title: Text(L10n.of(context)!.addAccount),
      //       )
      //     : null,
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          AppConfig.applicationName,
        ),
      ),
      // Pangea#
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // display a prominent banner to import session for TOR browser
          // users. This feature is just some UX sugar as TOR users are
          // usually forced to logout as TOR browser is non-persistent
          // #Pangea
          // AnimatedContainer(
          //   height: controller.isTorBrowser ? 64 : 0,
          //   duration: FluffyThemes.animationDuration,
          //   curve: FluffyThemes.animationCurve,
          //   clipBehavior: Clip.hardEdge,
          //   decoration: const BoxDecoration(),
          //   child: Material(
          //     clipBehavior: Clip.hardEdge,
          //     borderRadius:
          //         const BorderRadius.vertical(bottom: Radius.circular(8)),
          //     color: theme.colorScheme.surface,
          //     child: ListTile(
          //       leading: const Icon(Icons.vpn_key),
          //       title: Text(L10n.of(context)!.hydrateTor),
          //       subtitle: Text(L10n.of(context)!.hydrateTorLong),
          //       trailing: const Icon(Icons.chevron_right_outlined),
          //       onTap: controller.restoreBackup,
          //     ),
          //   ),
          // ),
          // if (MediaQuery.of(context).size.height > 512)
          //   ConstrainedBox(
          //     constraints: BoxConstraints(
          //       maxHeight: MediaQuery.of(context).size.height / 4,
          //     ),
          //     child: Image.asset(
          //       'assets/banner_transparent.png',
          //       alignment: Alignment.center,
          //       repeat: ImageRepeat.repeat,
          //     ),
          //   ),
          // Padding(
          //   padding: const EdgeInsets.all(32.0),
          //   child: TextField(
          //     onChanged: controller.tryCheckHomeserverActionWithCooldown,
          //     onEditingComplete:
          //         controller.tryCheckHomeserverActionWithoutCooldown,
          //     onSubmitted: controller.tryCheckHomeserverActionWithoutCooldown,
          //     onTap: controller.tryCheckHomeserverActionWithCooldown,
          //     controller: controller.homeserverController,
          //     autocorrect: false,
          //     keyboardType: TextInputType.url,
          //     decoration: InputDecoration(
          //       prefixIcon: controller.isLoading
          //           ? Container(
          //               width: 16,
          //               height: 16,
          //               alignment: Alignment.center,
          //               child: const SizedBox(
          //                 width: 16,
          //                 height: 16,
          //                 child: CircularProgressIndicator.adaptive(
          //                   strokeWidth: 2,
          //                 ),
          //               ),
          //             )
          //           : const Icon(Icons.search_outlined),
          //       filled: false,
          //       border: OutlineInputBorder(
          //         borderRadius: BorderRadius.circular(AppConfig.borderRadius),
          //       ),
          //       hintText: AppConfig.defaultHomeserver,
          //       labelText: L10n.of(context)!.homeserver,
          //       errorText: controller.error,
          //       suffixIcon: IconButton(
          //         onPressed: () {
          //           showDialog(
          //             context: context,
          //             builder: (context) => AlertDialog.adaptive(
          //               title: Text(L10n.of(context)!.whatIsAHomeserver),
          //               content: Linkify(
          //                 text: L10n.of(context)!.homeserverDescription,
          //               ),
          //               actions: [
          //                 TextButton(
          //                   onPressed: () => launchUrl(
          //                     Uri.https('servers.joinmatrix.org'),
          //                   ),
          //                   child: Text(
          //                     L10n.of(context)!.discoverHomeservers,
          //                   ),
          //                 ),
          //                 TextButton(
          //                   onPressed: Navigator.of(context).pop,
          //                   child: Text(L10n.of(context)!.close),
          //                 ),
          //               ],
          //             ),
          //           );
          //         },
          //         icon: const Icon(Icons.info_outlined),
          //       ),
          //     ),
          //   ),
          // ),
          // if (MediaQuery.of(context).size.height > 512) const Spacer(),
          // ListView(
          //   shrinkWrap: true,
          //   padding: const EdgeInsets.symmetric(
          //     horizontal: 32.0,
          //     vertical: 32.0,
          //   ),
          //   children: [
          //     TextButton(
          //       style: TextButton.styleFrom(
          //         textStyle: theme.textTheme.labelMedium,
          //         foregroundColor: theme.colorScheme.secondary,
          //       ),
          //       onPressed: controller.isLoggingIn || controller.isLoading
          //           ? null
          //           : controller.restoreBackup,
          //       child: Text(L10n.of(context)!.hydrate),
          //     ),
          //     if (controller.supportsPasswordLogin && controller.supportsSso)
          //       TextButton(
          //         style: TextButton.styleFrom(
          //           foregroundColor: theme.colorScheme.secondary,
          //           textStyle: theme.textTheme.labelMedium,
          //         ),
          //         onPressed: controller.isLoggingIn || controller.isLoading
          //             ? null
          //             : controller.login,
          //         child: Text(L10n.of(context)!.loginWithMatrixId),
          //       ),
          //     const SizedBox(height: 8.0),
          //     if (controller.supportsPasswordLogin || controller.supportsSso)
          //       ElevatedButton(
          //         style: ElevatedButton.styleFrom(
          //           backgroundColor: theme.colorScheme.primary,
          //           foregroundColor: theme.colorScheme.onPrimary,
          //         ),
          //         onPressed: controller.isLoggingIn || controller.isLoading
          //             ? null
          //             : controller.supportsSso
          //                 ? controller.ssoLoginAction
          //                 : controller.login,
          //         child: Text(L10n.of(context)!.next),
          //       ),
          //   ],
          // ),
          Expanded(
            child: controller.isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                    ),
                  )
                : ListView(
                    children: [
                      if (controller.error != null) ...[
                        const SizedBox(height: 12),
                        const Center(
                          child: Icon(
                            Icons.error_outline,
                            size: 48,
                            color: Colors.orange,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: Text(
                            controller.error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        const SizedBox(height: 36),
                      ] else
                        const SignupButtons(),
                      if (controller.identityProviders != null) ...[
                        ...controller.identityProviders!.map(
                          (provider) => Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Hero(
                              tag: "ssobutton ${provider.id ?? provider.name}",
                              child: PangeaSsoButton(
                                identityProvider: provider,
                                onPressed: () =>
                                    controller.ssoLoginAction(provider),
                              ),
                            ),
                          ),
                        ),
                        if (controller.supportsPasswordLogin)
                          Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Hero(
                              tag: 'signinButton',
                              child: ElevatedButton(
                                onPressed: controller.login,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const PangeaLogoSvg(width: 20),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ),
                                      child: Text(
                                        "${L10n.of(context)!.loginOrSignup} Pangea Chat",
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
          ),
          // Pangea#
        ],
      ),
    );
  }
}
