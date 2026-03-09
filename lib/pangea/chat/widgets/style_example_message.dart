import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/common/widgets/pressable_button.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/pangea/toolbar/reading_assistance/select_mode_buttons.dart';
import 'package:fluffychat/pangea/toolbar/reading_assistance/underline_text_widget.dart';
import 'package:fluffychat/pangea/toolbar/word_card/word_zoom_widget.dart';

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
    );
  }
}

class _StyleExampleMessage extends StatelessWidget {
  const _StyleExampleMessage();

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(
      color: ThemeData.dark().colorScheme.onPrimary,
      fontSize: AppConfig.messageFontSize * AppSettings.fontSizeFactor.value,
    );
    return Container(
      constraints: BoxConstraints(maxWidth: FluffyThemes.maxTimelineWidth),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          Colors.white.withAlpha(180),
          ThemeData.dark().colorScheme.primary,
        ),
        borderRadius: BorderRadius.circular(AppConfig.borderRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: RichText(
          text: TextSpan(
            children: [
              WidgetSpan(
                child: UnderlineText(
                  text: 'Hello',
                  style: textStyle,
                  underlineColor: ThemeData.dark().colorScheme.primaryContainer
                      .withAlpha(200),
                ),
              ),
              WidgetSpan(
                child: UnderlineText(text: ' world!', style: textStyle),
              ),
            ],
            style: textStyle,
          ),
        ),
      ),
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
                color: theme.colorScheme.primaryContainer,
                onPressed: null,
                colorFactor: theme.brightness == Brightness.light ? 0.55 : 0.3,
                builder: (_, _, _) => Container(
                  height: 40.0,
                  width: 40.0,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    mode.icon,
                    size: 20,
                    color: theme.colorScheme.onPrimaryContainer,
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
