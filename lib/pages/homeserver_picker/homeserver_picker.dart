import 'dart:async';

import 'package:adaptive_dialog/adaptive_dialog.dart';
import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pages/homeserver_picker/homeserver_picker_view.dart';
import 'package:fluffychat/pangea/utils/error_handler.dart';
import 'package:fluffychat/pangea/utils/firebase_analytics.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/tor_stub.dart'
    if (dart.library.html) 'package:tor_detector_web/tor_detector_web.dart';
import 'package:fluffychat/widgets/app_lock.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:matrix/matrix.dart';
import 'package:universal_html/html.dart' as html;

import '../../utils/localized_exception_extension.dart';

class HomeserverPicker extends StatefulWidget {
  final bool addMultiAccount;
  const HomeserverPicker({required this.addMultiAccount, super.key});

  @override
  HomeserverPickerController createState() => HomeserverPickerController();
}

class HomeserverPickerController extends State<HomeserverPicker> {
  bool isLoading = false;
  bool isLoggingIn = false;

  // #Pangea
  // final TextEditingController homeserverController = TextEditingController(
  //   text: AppConfig.defaultHomeserver,
  // );
  // Pangea#

  String? error;

  bool isTorBrowser = false;

  Future<void> _checkTorBrowser() async {
    if (!kIsWeb) return;

    Hive.openBox('test').then((value) => null).catchError(
      (e, s) async {
        await showOkAlertDialog(
          context: context,
          title: L10n.of(context)!.indexedDbErrorTitle,
          message: L10n.of(context)!.indexedDbErrorLong,
        );
        _checkTorBrowser();
      },
    );

    final isTor = await TorBrowserDetector.isTorBrowser;
    isTorBrowser = isTor;
  }

  String? _lastCheckedUrl;

  Timer? _checkHomeserverCooldown;

  tryCheckHomeserverActionWithCooldown([_]) {
    _checkHomeserverCooldown?.cancel();
    _checkHomeserverCooldown = Timer(
      const Duration(milliseconds: 500),
      checkHomeserverAction,
    );
  }

  tryCheckHomeserverActionWithoutCooldown([_]) {
    _checkHomeserverCooldown?.cancel();
    _lastCheckedUrl = null;
    checkHomeserverAction();
  }

  // #Pangea
  Map<String, dynamic>? _rawLoginTypes;
  // Pangea#

  /// Starts an analysis of the given homeserver. It uses the current domain and
  /// makes sure that it is prefixed with https. Then it searches for the
  /// well-known information and forwards to the login page depending on the
  /// login type.
  Future<void> checkHomeserverAction([_]) async {
    // #Pangea
    // homeserverController.text =
    //     homeserverController.text.trim().toLowerCase().replaceAll(' ', '-');

    // if (homeserverController.text.isEmpty) {
    //   setState(() {
    //     error = loginFlows = null;
    //     isLoading = false;
    //     Matrix.of(context).getLoginClient().homeserver = null;
    //   });
    //   return;
    // }
    // if (_lastCheckedUrl == homeserverController.text) return;

    // _lastCheckedUrl = homeserverController.text;
    _lastCheckedUrl = AppConfig.defaultHomeserver;
    // Pangea#
    setState(() {
      error = loginFlows = null;
      isLoading = true;
    });

    try {
      // #Pangea
      // var homeserver = Uri.parse(homeserverController.text);
      // if (homeserver.scheme.isEmpty) {
      //   homeserver = Uri.https(homeserverController.text, '');
      // }
      var homeserver = Uri.parse(AppConfig.defaultHomeserver);
      if (homeserver.scheme.isEmpty) {
        homeserver = Uri.https(AppConfig.defaultHomeserver, '');
      }
      // Pangea#
      final client = Matrix.of(context).getLoginClient();
      final (_, _, loginFlows) = await client.checkHomeserver(homeserver);
      this.loginFlows = loginFlows;
      // #Pangea
      if (supportsSso) {
        _rawLoginTypes = await client.request(
          RequestType.GET,
          '/client/v3/login',
        );
      }
      // Pangea#
    } catch (e) {
      setState(
        () => error = (e).toLocalizedString(
          context,
          ExceptionContext.checkHomeserver,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  List<LoginFlow>? loginFlows;

  bool _supportsFlow(String flowType) =>
      loginFlows?.any((flow) => flow.type == flowType) ?? false;

  bool get supportsSso => _supportsFlow('m.login.sso');

  bool isDefaultPlatform =
      (PlatformInfos.isMobile || PlatformInfos.isWeb || PlatformInfos.isMacOS);

  bool get supportsPasswordLogin => _supportsFlow('m.login.password');

  void ssoLoginAction(
    // #Pangea
    IdentityProvider provider,
    // Pangea#
  ) async {
    final redirectUrl = kIsWeb
        ? Uri.parse(html.window.location.href)
            .resolveUri(
              Uri(pathSegments: ['auth.html']),
            )
            .toString()
        : isDefaultPlatform
            ? '${AppConfig.appOpenUrlScheme.toLowerCase()}://login'
            : 'http://localhost:3001//login';

    final url = Matrix.of(context).getLoginClient().homeserver!.replace(
      // #Pangea
      // path: '/_matrix/client/v3/login/sso/redirect',
      path:
          '/_matrix/client/v3/login/sso/redirect${provider.id == null ? '' : '/${provider.id}'}',
      // Pangea#
      queryParameters: {'redirectUrl': redirectUrl},
    );

    final urlScheme = isDefaultPlatform
        ? Uri.parse(redirectUrl).scheme
        : "http://localhost:3001";

    // #Pangea
    // final result = await FlutterWebAuth2.authenticate(
    //   url: url.toString(),
    //   callbackUrlScheme: urlScheme,
    // );
    String result;
    try {
      result = await FlutterWebAuth2.authenticate(
        url: url.toString(),
        callbackUrlScheme: urlScheme,
      );
    } catch (err) {
      if (err is PlatformException && err.code == 'CANCELED') {
        debugPrint("user cancelled SSO login");
        return;
      }
      ErrorHandler.logError(
        e: err,
        s: StackTrace.current,
      );
      return;
    }
    // Pangea#
    final token = Uri.parse(result).queryParameters['loginToken'];
    if (token?.isEmpty ?? false) return;

    setState(() {
      error = null;
      isLoading = isLoggingIn = true;
    });
    try {
      // #Pangea
      final loginRes = await Matrix.of(context).getLoginClient().login(
            // await Matrix.of(context).getLoginClient().login(
            // Pangea#
            LoginType.mLoginToken,
            token: token,
            initialDeviceDisplayName: PlatformInfos.clientName,
          );
      // #Pangea
      GoogleAnalytics.login(provider.name!, loginRes.userId);
      // Pangea#
    } catch (e) {
      setState(() {
        error = e.toLocalizedString(context);
      });
    } finally {
      if (mounted) {
        setState(() {
          // #Pangea
          // isLoading = isLoggingIn = false;
          isLoggingIn = false;
          // Pangea#
        });
      }
    }
  }

  void login() => context.push(
        '${GoRouter.of(context).routeInformationProvider.value.uri.path}/login',
      );

  @override
  void initState() {
    _checkTorBrowser();
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(checkHomeserverAction);
  }

  @override
  Widget build(BuildContext context) => HomeserverPickerView(this);

  Future<void> restoreBackup() async {
    final picked = await AppLock.of(context).pauseWhile(
      FilePicker.platform.pickFiles(withData: true),
    );
    final file = picked?.files.firstOrNull;
    if (file == null) return;
    setState(() {
      error = null;
      isLoading = isLoggingIn = true;
    });
    try {
      final client = Matrix.of(context).getLoginClient();
      await client.importDump(String.fromCharCodes(file.bytes!));
      Matrix.of(context).initMatrix();
    } catch (e, s) {
      setState(() {
        error = e.toLocalizedString(context);
      });
      // #Pangea
      ErrorHandler.logError(e: e, s: s);
      // Pangea#
    } finally {
      if (mounted) {
        setState(() {
          isLoading = isLoggingIn = false;
        });
      }
    }
  }

  // #Pangea
  List<IdentityProvider>? get identityProviders {
    final loginTypes = _rawLoginTypes;
    if (loginTypes == null) return null;
    final List? rawProviders =
        loginTypes.tryGetList('flows')?.singleWhereOrNull(
                  (flow) => flow['type'] == AuthenticationTypes.sso,
                )['identity_providers'] ??
            [
              {'id': null},
            ];
    if (rawProviders == null) return null;
    final list =
        rawProviders.map((json) => IdentityProvider.fromJson(json)).toList();
    if (PlatformInfos.isCupertinoStyle) {
      list.sort((a, b) => a.brand == 'apple' ? -1 : 1);
    }
    return list;
  }
  // Pangea#
}

class IdentityProvider {
  final String? id;
  final String? name;
  final String? icon;
  final String? brand;

  IdentityProvider({this.id, this.name, this.icon, this.brand});

  factory IdentityProvider.fromJson(Map<String, dynamic> json) =>
      IdentityProvider(
        id: json['id'],
        name: json['name'],
        icon: json['icon'],
        brand: json['brand'],
      );
}
