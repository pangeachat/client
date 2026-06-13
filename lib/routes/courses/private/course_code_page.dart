import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/analytics_access/join_room_analytics_consent_handler.dart';
import 'package:fluffychat/features/join_codes/space_code_controller.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/spaces/space_constants.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class CourseCodePage extends StatefulWidget {
  const CourseCodePage({super.key});

  @override
  State<CourseCodePage> createState() => CourseCodePageState();
}

class CourseCodePageState extends State<CourseCodePage> {
  final TextEditingController _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _codeController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  String get _code => _codeController.text.trim();

  Future<void> _submit() async {
    if (_code.isEmpty) {
      return;
    }

    final client = Matrix.of(context).client;
    final result = await SpaceCodeController.joinSpaceWithCode(
      _code,
      context: context,
      client: client,
    );
    final joinResp = result.result;
    if (joinResp == null) return;

    final room = client.getRoomById(joinResp.roomId);
    if (room == null) return;

    final handler = JoinRoomAnalyticsConsentHandler(joinResp, room);
    final joinedRoomId = await handler.handle(context);
    if (joinedRoomId == null) return;

    room.isSpace
        ? context.go('/rooms/spaces/$joinedRoomId/details')
        : context.go('/rooms/$joinedRoomId');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        // world_v2: back returns to the Add-course hub, close to the map.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => context.go('/courses'),
        ),
        title: Text(L10n.of(context).joinWithCode),
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
                Column(
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
