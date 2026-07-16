import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/join_codes/space_code_controller.dart';
import 'package:fluffychat/features/navigation/token_params/add_course_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/spaces/space_constants.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class CourseCodePage extends StatefulWidget {
  /// A code delivered by an inbound join link (the `addcourse` token's
  /// `private/<code>` leaf — see LegacyRedirects, #7524). Prefilled and
  /// submitted once, running the exact join a manual entry performs. The
  /// trigger is consumed when the submit COMPLETES (the coded URL is
  /// history-REPLACED with the manual `private` page), so back or refresh
  /// after the flow never re-fires it. Consuming it up front looked safer but
  /// remounted this page mid-join — the URL rewrite changes the panel's
  /// identity key — orphaning the post-join navigation and stranding the user
  /// on the join page as a secret member of the course (#7579). A refresh
  /// MID-join re-fires harmlessly: the knock+join are idempotent server-side.
  final String? initialCode;
  final Widget closeButton;

  const CourseCodePage({
    super.key,
    this.initialCode,
    required this.closeButton,
  });

  /// Whether a change of [initialCode] (from [previous] to [next] — null for
  /// a fresh mount) should trigger the one-shot prefill + submit. Fires only
  /// for a NEW non-empty code: the null the URL-consuming replace delivers,
  /// and a rebuild carrying the same code, must not re-fire. Pure —
  /// unit-tested (course_code_auto_submit_test.dart).
  static bool shouldAutoSubmit(String? previous, String? next) {
    final code = next?.trim();
    if (code == null || code.isEmpty) return false;
    return previous?.trim() != code;
  }

  @override
  State<CourseCodePage> createState() => CourseCodePageState();
}

class CourseCodePageState extends State<CourseCodePage> {
  final TextEditingController _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _codeController.addListener(() => setState(() {}));
    if (CourseCodePage.shouldAutoSubmit(null, widget.initialCode)) {
      _autoSubmit();
    }
  }

  @override
  void didUpdateWidget(covariant CourseCodePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new code arriving while the page is already mounted (an in-app deep
    // link changing only the token param) must prefill and submit too —
    // initState won't re-run for a param-only change.
    if (CourseCodePage.shouldAutoSubmit(
      oldWidget.initialCode,
      widget.initialCode,
    )) {
      _autoSubmit();
    }
  }

  /// One-shot inbound-code submit; the trigger is consumed at completion
  /// (see [CourseCodePage.initialCode]).
  void _autoSubmit() {
    _codeController.text = widget.initialCode!.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _submit(consumeInboundCode: true);
    });
  }

  /// History-replace the inbound-coded URL with the manual `private` page so
  /// back/refresh never re-fire the join. Rewriting this panel's own URL
  /// changes its identity key and remounts it, so any follow-up navigation
  /// must happen in the SAME tick (#7579).
  void _consumeInboundCode() {
    context.replace(
      WorkspaceNav.openAddCoursePage(
        GoRouterState.of(context).uri,
        AddCourseSubpageEnum.private,
      ),
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  String get _code => _codeController.text.trim();

  Future<void> _submit({bool consumeInboundCode = false}) async {
    if (_code.isEmpty) {
      return;
    }

    final client = Matrix.of(context).client;
    final result = await SpaceCodeController.joinSpaceWithCode(
      _code,
      context: context,
      client: client,
    );
    if (!mounted) return;

    final joinResp = result.result;
    if (joinResp == null) {
      // Failed join (error already surfaced by the loading dialog): consume
      // the trigger so a refresh lands on the manual page, not a re-fire.
      if (consumeInboundCode) _consumeInboundCode();
      return;
    }

    final target = await SpaceCodeController.resolveJoinedTarget(
      context,
      client,
      joinResp,
    );
    if (!mounted) return;
    // Consume, then hop, in one tick: the consume's rebuild remounts this
    // page, so a navigation scheduled any later would be orphaned (#7579).
    if (consumeInboundCode) _consumeInboundCode();
    if (target != null) {
      SpaceCodeController.goToJoinedTarget(context, target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        // world_v2: back returns to the Add-course hub, close to the map.
        leading: widget.closeButton,
        title: Text(
          L10n.of(context).joinWithCode,
          style: FluffyThemes.isColumnMode(context)
              ? theme.textTheme.titleLarge
              : theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
        ),
        centerTitle: false,
        titleSpacing: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: L10n.of(context).close,
            onPressed: () => context.go('/'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(20.0),
            constraints: const BoxConstraints(maxWidth: 350, maxHeight: 600),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SvgPicture.network(
                  "${AppConfig.assetsBaseURL}/${SpaceConstants.mapUnlockFileName}",
                  width: 100.0,
                  height: 100.0,
                  colorFilter: ColorFilter.mode(
                    theme.colorScheme.onSurface,
                    BlendMode.srcIn,
                  ),
                ),

                FocusTraversalGroup(
                  policy: OrderedTraversalPolicy(),
                  child: Column(
                    spacing: 16.0,
                    children: [
                      Text(
                        L10n.of(context).enterCodeToJoin,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextFormField(
                        controller: _codeController,
                        decoration: InputDecoration(
                          hintText: L10n.of(context).courseCodeHint,
                        ),
                        onFieldSubmitted: (_) => _submit(),
                        inputFormatters: [LengthLimitingTextInputFormatter(10)],
                      ),
                      ElevatedButton(
                        onPressed: _code.isNotEmpty ? _submit : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primaryContainer,
                          foregroundColor: theme.colorScheme.onPrimaryContainer,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [Text(L10n.of(context).submit)],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
