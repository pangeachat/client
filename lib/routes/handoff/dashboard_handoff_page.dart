import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/shared_signin/shared_signin_web.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// `/handoff/dashboard`: the teacher dashboard asks whether this browser is
/// signed in to the app (admin-dash#235). The page answers and leaves for the
/// configured dashboard; with nothing to answer it goes into the app.
/// routing.instructions.md § Signing in from the dashboard.
class DashboardHandoffPage extends StatefulWidget {
  const DashboardHandoffPage({super.key});

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
    final answered = await SharedSignIn.answerDashboard(Matrix.of(context));
    if (!answered && mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator.adaptive()));
}
