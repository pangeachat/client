import 'dart:developer';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pangea/constants/bot_mode.dart';
import 'package:fluffychat/pangea/constants/pangea_event_types.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension/pangea_room_extension.dart';
import 'package:fluffychat/pangea/models/bot_options_model.dart';
import 'package:fluffychat/pangea/utils/bot_name.dart';
import 'package:fluffychat/pangea/utils/error_handler.dart';
import 'package:fluffychat/pangea/widgets/common/bot_face_svg.dart';
import 'package:fluffychat/pangea/widgets/conversation_bot/conversation_bot_settings_form.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:matrix/matrix.dart';

class ConversationBotSettings extends StatefulWidget {
  final Room room;

  const ConversationBotSettings({
    super.key,
    required this.room,
  });

  @override
  ConversationBotSettingsState createState() => ConversationBotSettingsState();
}

class ConversationBotSettingsState extends State<ConversationBotSettings> {
  Future<void> setBotOptions(BotOptionsModel botOptions) async {
    try {
      await Matrix.of(context).client.setRoomStateWithKey(
            widget.room.id,
            PangeaEventTypes.botOptions,
            '',
            botOptions.toJson(),
          );
    } catch (err, stack) {
      debugger(when: kDebugMode);
      ErrorHandler.logError(e: err, s: stack);
    }
  }

  Future<void> showBotOptionsDialog() async {
    final BotOptionsModel? newBotOptions = await showDialog<BotOptionsModel?>(
      context: context,
      builder: (BuildContext context) =>
          ConversationBotSettingsDialog(room: widget.room),
    );

    if (newBotOptions != null) {
      setBotOptions(newBotOptions);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: Text(
              L10n.of(context)!.botConfig,
              style: TextStyle(
                color: Theme.of(context).colorScheme.secondary,
                fontWeight: FontWeight.bold,
              ),
            ),
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              foregroundColor: Theme.of(context).textTheme.bodyLarge!.color,
              child: const BotFace(
                width: 30.0,
                expression: BotExpression.idle,
              ),
            ),
            trailing: const Icon(Icons.settings),
            onTap: showBotOptionsDialog,
          ),
        ],
      ),
    );
  }
}

class ConversationBotSettingsDialog extends StatefulWidget {
  final Room room;

  const ConversationBotSettingsDialog({
    super.key,
    required this.room,
  });

  @override
  ConversationBotSettingsDialogState createState() =>
      ConversationBotSettingsDialogState();
}

class ConversationBotSettingsDialogState
    extends State<ConversationBotSettingsDialog> {
  late BotOptionsModel botOptions;
  bool addBot = false;

  final TextEditingController discussionTopicController =
      TextEditingController();
  final TextEditingController discussionKeywordsController =
      TextEditingController();
  final TextEditingController customSystemPromptController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    botOptions = widget.room.botOptions != null
        ? BotOptionsModel.fromJson(widget.room.botOptions?.toJson())
        : BotOptionsModel();

    widget.room.botIsInRoom.then((bool isBotRoom) {
      setState(() => addBot = isBotRoom);
    });

    discussionKeywordsController.text = botOptions.discussionKeywords ?? "";
    discussionTopicController.text = botOptions.discussionTopic ?? "";
    customSystemPromptController.text = botOptions.customSystemPrompt ?? "";
  }

  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  void updateFromTextControllers() {
    botOptions.discussionTopic = discussionTopicController.text;
    botOptions.discussionKeywords = discussionKeywordsController.text;
    botOptions.customSystemPrompt = customSystemPromptController.text;
  }

  void onUpdateChatMode(String? mode) {
    setState(() => botOptions.mode = mode ?? BotMode.discussion);
  }

  void onUpdateBotLanguage(String? language) {
    setState(() => botOptions.targetLanguage = language);
  }

  void onUpdateBotVoice(String? voice) {
    setState(() => botOptions.targetVoice = voice);
  }

  void onUpdateBotLanguageLevel(int? level) {
    setState(() => botOptions.languageLevel = level);
  }

  @override
  Widget build(BuildContext context) {
    final dialogContent = Form(
      key: formKey,
      child: Container(
        padding: const EdgeInsets.all(16),
        constraints: kIsWeb
            ? const BoxConstraints(
                maxWidth: 450,
                maxHeight: 725,
              )
            : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                    ),
                    child: Text(
                      L10n.of(context)!.botConfig,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(null),
                  ),
                ],
              ),
              SwitchListTile(
                title: Text(
                  L10n.of(context)!.conversationBotStatus,
                ),
                value: addBot,
                onChanged: (bool value) {
                  setState(() => addBot = value);
                },
                contentPadding: const EdgeInsets.all(4),
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: 20),
                      AnimatedOpacity(
                        duration: FluffyThemes.animationDuration,
                        opacity: addBot ? 1.0 : 0.5,
                        child: ConversationBotSettingsForm(
                          botOptions: botOptions,
                          discussionKeywordsController:
                              discussionKeywordsController,
                          discussionTopicController: discussionTopicController,
                          customSystemPromptController:
                              customSystemPromptController,
                          enabled: addBot,
                          onUpdateBotMode: onUpdateChatMode,
                          onUpdateBotLanguage: onUpdateBotLanguage,
                          onUpdateBotVoice: onUpdateBotVoice,
                          onUpdateBotLanguageLevel: onUpdateBotLanguageLevel,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop(null);
                    },
                    child: Text(L10n.of(context)!.cancel),
                  ),
                  const SizedBox(width: 20),
                  TextButton(
                    onPressed: () async {
                      final isValid = formKey.currentState!.validate();
                      if (!isValid) return;

                      updateFromTextControllers();

                      final bool isBotRoomMember =
                          await widget.room.botIsInRoom;
                      if (addBot && !isBotRoomMember) {
                        await widget.room.invite(BotName.byEnvironment);
                      } else if (!addBot && isBotRoomMember) {
                        await widget.room.kick(BotName.byEnvironment);
                      }

                      Navigator.of(context).pop(botOptions);
                    },
                    child: Text(L10n.of(context)!.confirm),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return kIsWeb
        ? Dialog(child: dialogContent)
        : Dialog.fullscreen(child: dialogContent);
  }
}
