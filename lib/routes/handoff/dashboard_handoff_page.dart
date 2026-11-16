import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/shared_signin/shared_signin_web.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The teacher dashboard's requests to this app (admin-dash#235):
/// `/handoff/dashboard` asks whether this browser is signed in to the app,
/// `/handoff/signout` asks it to sign this browser out too. The page answers
/// and leaves for the configured dashboard; with nothing to answer it goes
/// into the app. routing.instructions.md § Signing in from the dashboard.
class DashboardHandoffPage extends StatefulWidget {
  final bool signOut;

  const DashboardHandoffPage({super.key, this.signOut = false});

  @override
  State<DashboardHandoffPage> createState() => _DashboardHandoffPageState();
}

class _DashboardHandoffPageState extends State<DashboardHandoffPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _answer());
  }

  Future<void> _answer() async {
    if (!mounted) return;
    final matrix = Matrix.of(context);
    final answered = widget.signOut
        ? await SharedSignIn.answerSignOut(matrix)
        : await SharedSignIn.answerDashboard(matrix);
    if (!answered && mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator.adaptive()));
}
