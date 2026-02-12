import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/widgets/pangea_logo_svg.dart';
import 'package:fluffychat/pangea/join_codes/space_code_repo.dart';
import 'package:fluffychat/pangea/login/widgets/app_config_dialog.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class LoginOrSignupView extends StatefulWidget {
  const LoginOrSignupView({super.key});

  @override
  State<LoginOrSignupView> createState() => LoginOrSignupViewState();
}

class LoginOrSignupViewState extends State<LoginOrSignupView> {
  List<AppConfigOverride> _overrides = [];

  @override
  void initState() {
    super.initState();
    _loadOverrides();
  }

  String? get _cachedSpaceCode => SpaceCodeRepo.spaceCode;

  Future<void> _loadOverrides() async {
    final overrides = await Environment.getAppConfigOverrides();
    if (mounted) {
      setState(() => _overrides = overrides);
    }
  }

  Future<void> _setEnvironment() async {
    if (_overrides.isEmpty) return;

    final resp = await showDialog<AppConfigOverride?>(
      context: context,
      builder: (context) => AppConfigDialog(overrides: _overrides),
    );

    await Environment.setAppConfigOverride(resp);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        actions: Environment.isStagingEnvironment && _overrides.isNotEmpty
            ? [
                IconButton(
                  tooltip: L10n.of(context).settings,
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: _setEnvironment,
                ),
              ]
            : null,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Column(
              spacing: 50.0,
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  spacing: 12.0,
                  children: [
                    PangeaLogoSvg(width: 50.0, forceColor: theme.colorScheme.onSurface),
                    Text(
                      AppSettings.applicationName.value,
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Text(
                  L10n.of(context).appDescription,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                Column(
                  spacing: 16.0,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
                      // push instead of go so the app bar back button doesn't go to the language selection page
                      // https://github.com/pangeachat/client/issues/4421
                      onPressed: () =>
                          context.push(_cachedSpaceCode != null ? '/home/language/signup' : '/home/language'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        foregroundColor: theme.colorScheme.onPrimaryContainer,
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text(L10n.of(context).start)]),
                    ),
                    ElevatedButton(
                      onPressed: () => context.go('/home/login'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        foregroundColor: theme.colorScheme.onPrimaryContainer,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [Text(L10n.of(context).loginToAccount)],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
