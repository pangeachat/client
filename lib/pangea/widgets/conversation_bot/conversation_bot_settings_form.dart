import 'package:fluffychat/pangea/constants/bot_mode.dart';
import 'package:fluffychat/pangea/models/bot_options_model.dart';
import 'package:fluffychat/pangea/widgets/conversation_bot/conversation_bot_mode_dynamic_zone.dart';
import 'package:fluffychat/pangea/widgets/conversation_bot/conversation_bot_mode_select.dart';
import 'package:fluffychat/pangea/widgets/space/language_level_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';

class ConversationBotSettingsForm extends StatefulWidget {
  final BotOptionsModel botOptions;

  const ConversationBotSettingsForm({
    super.key,
    required this.botOptions,
  });

  @override
  ConversationBotSettingsFormState createState() =>
      ConversationBotSettingsFormState();
}

class ConversationBotSettingsFormState
    extends State<ConversationBotSettingsForm> {
  final formKey = GlobalKey<FormState>();

  late BotOptionsModel botOptions;

  @override
  void initState() {
    super.initState();
    botOptions = widget.botOptions;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Text(
            L10n.of(context)!.conversationLanguageLevel,
            style: TextStyle(
              color: Theme.of(context).colorScheme.secondary,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        LanguageLevelDropdown(
          initialLevel: botOptions.languageLevel,
          onChanged: (int? newValue) => {
            setState(() {
              botOptions.languageLevel = newValue!;
            }),
          },
        ),
        Text(
          L10n.of(context)!.conversationBotModeSelectDescription,
          style: TextStyle(
            color: Theme.of(context).colorScheme.secondary,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        ConversationBotModeSelect(
          initialMode: botOptions.mode,
          onChanged: (String? mode) => {
            setState(() {
              botOptions.mode = mode ?? BotMode.discussion;
            }),
          },
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: ConversationBotModeDynamicZone(
            initialBotOptions: botOptions,
            onChanged: (BotOptionsModel? newOptions) {
              if (newOptions != null) {
                setState(() {
                  botOptions = newOptions;
                });
              }
            },
          ),
        ),
      ],
    );
  }
}
