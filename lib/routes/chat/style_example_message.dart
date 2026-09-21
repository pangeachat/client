import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/bot/widgets/bot_face_svg.dart';
import 'package:fluffychat/pangea/common/widgets/pressable_button.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/routes/chat/events/tokens/underline_text_widget.dart';
import 'package:fluffychat/routes/chat/toolbar/reading_assistance/select_mode_buttons.dart';
import 'package:fluffychat/routes/chat/toolbar/word_card/word_zoom_widget.dart';
import 'package:fluffychat/widgets/avatar.dart';

class StyleExampleMessage extends StatelessWidget {
  const StyleExampleMessage({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(right: 12, bottom: 12, top: 12),
      child: Column(
        spacing: 4.0,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(width: double.infinity),
          _StyleExampleWordCard(),
          _StyleExampleMessage(),
          _StyleExampleToolbarButtons(),
          // The bot wears the learner's chosen colour, so the swatch they are
          // about to tap changes it. Shown as a reply on the other side, with
          // its avatar, because that is where they meet it in a chat.
          Align(
            alignment: Alignment.centerLeft,
            child: _StyleExampleBotMessage(),
          ),
        ],
      ),
    );
  }
}

class _StyleExampleWordCard extends StatelessWidget {
  const _StyleExampleWordCard();

  @override
  Widget build(BuildContext context) {
    return WordZoomWidget(
      token: PangeaTokenText(offset: 0, content: 'Hello', length: 4),
      langCode: 'en',
      construct: ConstructIdentifier(
        category: 'INTJ',
        lemma: 'hello',
        type: ConstructTypeEnum.vocab,
      ),
      pos: 'INTJ',
      enableEmojiReactions: false,
      enableEmojiSelection: false,
    );
  }
}

class _StyleExampleMessage extends StatelessWidget {
  const _StyleExampleMessage();

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(
      color: Theme.of(context).colorScheme.onPrimary,
      fontSize: AppConfig.messageFontSize,
    );
    return Container(
      constraints: BoxConstraints(maxWidth: FluffyThemes.maxTimelineWidth),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(AppConfig.borderRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: RichText(
          textScaler: MediaQuery.textScalerOf(context),
          text: TextSpan(
            children: [
              // A WidgetSpan child is already scaled by the placeholder it
              // sits in; scaling its text here too squares the device text
              // size (#7719).
              WidgetSpan(
                child: MediaQuery.withNoTextScaling(
                  child: UnderlineText(
                    text: 'Hello',
                    style: textStyle,
                    underlineColor: Theme.of(
                      context,
                    ).colorScheme.onPrimary.withAlpha(200),
                  ),
                ),
              ),
              WidgetSpan(
                child: MediaQuery.withNoTextScaling(
                  child: UnderlineText(text: ' world!', style: textStyle),
                ),
              ),
            ],
            style: textStyle,
          ),
        ),
      ),
    );
  }
}

class _StyleExampleBotMessage extends StatelessWidget {
  const _StyleExampleBotMessage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      spacing: 8.0,
      children: [
        // Still rather than animated: this is the face a message avatar wears
        // in a chat, and a settings page has no reason to run a state machine.
        const BotFace(
          width: Avatar.defaultSize,
          expression: BotExpression.idle,
          animate: false,
        ),
        Flexible(
          child: Container(
            constraints: const BoxConstraints(
              maxWidth: FluffyThemes.maxTimelineWidth,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppConfig.borderRadius),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Hello!',
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontSize: AppConfig.messageFontSize,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StyleExampleToolbarButtons extends StatelessWidget {
  const _StyleExampleToolbarButtons();

  @override
  Widget build(BuildContext context) {
    final allModes = [
      SelectMode.audio,
      SelectMode.translate,
      SelectMode.practice,
      SelectMode.emoji,
    ];

    final theme = Theme.of(context);
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        height: AppConfig.toolbarMenuHeight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(allModes.length, (index) {
            final mode = allModes[index];
            return Container(
              width: 45.0,
              alignment: Alignment.center,
              child: PressableButton(
                borderRadius: BorderRadius.circular(20),
                color: theme.toolbarButtonFill,
                onPressed: null,
                colorFactor: 0.3,
                builder: (_, _, _) => Container(
                  height: 40.0,
                  width: 40.0,
                  decoration: BoxDecoration(
                    color: theme.toolbarButtonFill,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    mode.icon,
                    size: 20,
                    color: theme.onToolbarButtonFill,
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
