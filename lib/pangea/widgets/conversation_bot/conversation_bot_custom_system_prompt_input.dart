import 'package:fluffychat/pangea/models/bot_options_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';

class ConversationBotCustomSystemPromptInput extends StatelessWidget {
  final BotOptionsModel initialBotOptions;
  // call this to update propagate changes to parents
  final void Function(BotOptionsModel) onChanged;

  const ConversationBotCustomSystemPromptInput({
    super.key,
    required this.initialBotOptions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    String customSystemPrompt = initialBotOptions.customSystemPrompt ?? "";

    final TextEditingController textFieldController =
        TextEditingController(text: customSystemPrompt);

    final GlobalKey<FormState> customSystemPromptFormKey =
        GlobalKey<FormState>();

    void setBotCustomSystemPromptAction() async {
      showDialog(
        context: context,
        useRootNavigator: false,
        builder: (BuildContext context) => AlertDialog(
          title: Text(
            L10n.of(context)!.conversationBotCustomZone_customSystemPromptLabel,
          ),
          content: Form(
            key: customSystemPromptFormKey,
            child: TextFormField(
              minLines: 1,
              maxLines: 10,
              maxLength: 1000,
              controller: textFieldController,
              onChanged: (value) {
                if (value.isNotEmpty) {
                  customSystemPrompt = value;
                }
              },
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'This field cannot be empty';
                }
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              child: Text(L10n.of(context)!.cancel),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text(L10n.of(context)!.ok),
              onPressed: () {
                if (customSystemPromptFormKey.currentState!.validate()) {
                  if (customSystemPrompt !=
                      initialBotOptions.customSystemPrompt) {
                    initialBotOptions.customSystemPrompt = customSystemPrompt;
                    onChanged.call(initialBotOptions);
                  }
                  Navigator.of(context).pop();
                }
              },
            ),
          ],
        ),
      );
    }

    return ListTile(
      onTap: setBotCustomSystemPromptAction,
      title: Text(
        initialBotOptions.customSystemPrompt ??
            L10n.of(context)!
                .conversationBotCustomZone_customSystemPromptPlaceholder,
      ),
      subtitle: customSystemPrompt.isEmpty
          ? Text(
              L10n.of(context)!
                  .conversationBotCustomZone_customSystemPromptEmptyError,
              style: const TextStyle(color: Colors.red),
            )
          : null,
    );
  }
}
