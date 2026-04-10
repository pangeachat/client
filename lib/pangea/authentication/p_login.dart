import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/pages/login/login.dart';
import 'package:fluffychat/pangea/authentication/login_loading_dialog.dart';
import 'package:fluffychat/pangea/authentication/store_login_method_repo.dart';
import 'package:fluffychat/pangea/common/utils/firebase_analytics.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/matrix.dart';

void pLoginAction({
  required Function(bool) setLoadingSignIn,
  required String username,
  required String password,
  required BuildContext context,
}) async {
  setLoadingSignIn(true);
  await LoginMethodRepo.clearStoredLoginMethod();
  if (RegExp(r'^@(\w+):').hasMatch(username)) {
    username = RegExp(r'^@(\w+):').allMatches(username).elementAt(0).group(1)!;
  }

  AuthenticationIdentifier identifier;
  if (username.isEmail) {
    identifier = AuthenticationThirdPartyIdentifier(
      medium: 'email',
      address: username,
    );
  } else if (username.isPhoneNumber) {
    identifier = AuthenticationThirdPartyIdentifier(
      medium: 'msisdn',
      address: username,
    );
  } else {
    identifier = AuthenticationUserIdentifier(user: username);
  }

  final client = await Matrix.of(context).getLoginClient();
  await showAdaptiveDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) => LoginLoadingDialog(
      client: client,
      loginType: LoginType.mLoginPassword,
      identifier: identifier,
      password: password.trim(),
      initialDeviceDisplayName: PlatformInfos.clientName,
      onError: () => setLoadingSignIn(false),
    ),
  );

  if (!client.isLogged()) {
    setLoadingSignIn(false);
    return;
  }

  if (client.userID == null) {
    Logs().e("Login succeeded but userID is null");
    return;
  }

  await LoginMethodRepo.storeLoginMethod(
    userID: client.userID!,
    method: LoginMethod.email,
  );
  GoogleAnalytics.login("pangea", client.userID!);
}
