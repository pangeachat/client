import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/authentication/email_address_policy.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/firebase_analytics.dart';
import 'package:fluffychat/routes/home/signup/request_token_client_extension.dart';
import 'package:fluffychat/routes/home/signup/signup_failure.dart';
import 'package:fluffychat/routes/home/signup/signup_view.dart';
import 'package:fluffychat/routes/home/signup/signup_with_email_view.dart';
import 'package:fluffychat/routes/home/store_login_method_repo.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class SignupPage extends StatefulWidget {
  final bool withEmail;

  const SignupPage({this.withEmail = false, super.key});

  @override
  SignupPageController createState() => SignupPageController();
}

class SignupPageController extends State<SignupPage> {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController emailController = TextEditingController();

  String? usernameText;
  String? passwordText;
  String? emailText;

  bool loadingSignup = false;
  bool showPassword = false;
  bool noEmailWarningConfirmed = false;
  bool displaySecondPasswordField = false;

  PreviousLoginInfo? prevInfo;

  @override
  void initState() {
    super.initState();

    usernameController.addListener(() {
      _setStateOnTextChange(usernameText, usernameController.text);
      usernameText = usernameController.text;
    });

    passwordController.addListener(() {
      _setStateOnTextChange(passwordText, passwordController.text);
      passwordText = passwordController.text;
    });

    emailController.addListener(() {
      _setStateOnTextChange(emailText, emailController.text);
      emailText = emailController.text;
    });

    _setPreviousLoginMethod();
  }

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    emailController.dispose();
    loadingSignup = false;
    super.dispose();
  }

  void setSignupError(String? error) {
    signupError = error;
    if (mounted) setState(() {});
  }

  bool get enableSignUp =>
      !loadingSignup &&
      emailController.text.isNotEmpty &&
      usernameController.text.isNotEmpty &&
      passwordController.text.isNotEmpty;

  void _setStateOnTextChange(String? oldText, String newText) {
    if ((oldText == null || oldText.isEmpty) && (newText.isNotEmpty)) {
      setState(() {});
    }
    if ((oldText != null && oldText.isNotEmpty) && (newText.isEmpty)) {
      setState(() {});
    }
  }

  static const int minPassLength = 6;

  void toggleShowPassword() => setState(() => showPassword = !showPassword);

  // String? get domain => VRouter.of(context).queryParameters['domain'];

  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  void onPasswordType(String text) {
    if (text.length >= minPassLength && !displaySecondPasswordField) {
      setState(() {
        displaySecondPasswordField = true;
      });
    }
  }

  String? password1TextFieldValidator(String? value) {
    if (value!.isEmpty) {
      return L10n.of(context).chooseAStrongPassword;
    }
    if (value.length < minPassLength) {
      return L10n.of(
        context,
      ).pleaseChooseAtLeastChars(minPassLength.toString());
    }
    return null;
  }

  String? password2TextFieldValidator(String? value) {
    if (value!.isEmpty) {
      return L10n.of(context).repeatPassword;
    }
    if (value != passwordController.text) {
      return L10n.of(context).passwordsDoNotMatch;
    }
    return null;
  }

  String? emailTextFieldValidator(String? value) {
    if (value == null || value.isEmpty) {
      return L10n.of(context).pleaseEnterEmail;
    }
    if (!EmailAddressPolicy.isValid(value)) {
      return L10n.of(context).pleaseEnterValidEmail;
    }
    return null;
  }

  String? signupError;

  void signup([dynamic _]) async {
    setSignupError(null);
    final valid = formKey.currentState!.validate();
    if (!valid) return;
    setState(() => loadingSignup = true);

    final resp = await showFutureLoadingDialog(
      context: context,
      future: _signupFuture,
    );

    if (!mounted) return;
    setState(() => loadingSignup = false);

    // An unexpected failure was reported and shown by the dialog itself.
    if (resp.isError) return;

    final failure = resp.asValue?.value;
    if (failure == null) {
      context.go('/registration');
      return;
    }
    setSignupError(failure.localizedMessage(context));
  }

  /// Null on success. An expected outcome — a taken username, a rate limit, a
  /// cancelled request — comes back as a value so it stays off the error path
  /// and out of Sentry (#8370); anything else propagates and is reported.
  Future<SignupFailure?> _signupFuture() async {
    try {
      await _register();
      return null;
    } catch (e) {
      final failure = SignupFailure.from(e);
      if (failure == null) rethrow;
      return failure;
    }
  }

  Future<void> _register() async {
    await LoginMethodRepo.clearStoredLoginMethod();

    final client = await Matrix.of(context).getLoginClient();
    final email = emailController.text;

    final displayname = usernameController.text;
    final localPart = displayname.toLowerCase().replaceAll(' ', '_');

    if (email.isNotEmpty) {
      Matrix.of(context).currentClientSecret = DateTime.now()
          .millisecondsSinceEpoch
          .toString();

      Matrix.of(context).currentRegistrationEmail = email;
      Matrix.of(context).currentRegisrationUsername = localPart;
      Matrix.of(context).currentSendAttempt = 0;
      Matrix.of(context).currentThreepidCreds = await client
          .requestTokenToRegister(
            Matrix.of(context).currentClientSecret,
            email,
            localPart,
            0,
          );
    }

    GoogleAnalytics.prepareLogin("pangea");
    try {
      await client.uiaRequestBackground<RegisterResponse?>(
        (auth) => client.register(
          username: localPart,
          password: passwordController.text,
          initialDeviceDisplayName: PlatformInfos.clientName,
          auth: auth,
        ),
      );
    } catch (_) {
      GoogleAnalytics.cancelPendingLogin();
      rethrow;
    }

    if (!client.isLogged()) {
      GoogleAnalytics.cancelPendingLogin();
      throw Exception(L10n.of(context).oopsSomethingWentWrong);
    }

    await LoginMethodRepo.storeLoginMethod(
      userID: client.userID!,
      method: LoginMethod.email,
    );
    GoogleAnalytics.signUp("pangea");

    if (displayname != localPart && client.userID != null) {
      await client.setProfileField(client.userID!, 'displayname', {
        'displayname': displayname,
      });
    }
  }

  Future<void> _setPreviousLoginMethod() async {
    final loginMethod = await LoginMethodRepo.getStoredLoginMethod();
    if (!mounted) return;
    if (loginMethod != null) {
      setState(() => prevInfo = loginMethod);
    }
  }

  @override
  Widget build(BuildContext context) =>
      widget.withEmail ? SignupWithEmailView(this) : SignupPageView(this);
}
