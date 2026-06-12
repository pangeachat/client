import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/user/style_settings_repo.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'settings_chat_view.dart';

class SettingsChat extends StatefulWidget {
  const SettingsChat({super.key});

  @override
  SettingsChatController createState() => SettingsChatController();
}

class SettingsChatController extends State<SettingsChat> {
  // #Pangea
  Future<void> setUseActivityImageBackground(bool value) async {
    final userId = Matrix.of(context).client.userID!;
    AppConfig.useActivityImageAsChatBackground = value;
    setState(() {});
    await StyleSettingsRepo.setUseActivityImageBackground(userId, value);
  }
  // Pangea#

  @override
  Widget build(BuildContext context) => SettingsChatView(this);
}
