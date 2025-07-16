import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/bot/widgets/bot_face_svg.dart';
import 'package:fluffychat/pangea/subscription/pages/settings_subscription_view.dart';

enum FreeModeOptions {
  chat,
  create,
  bot,
  activities,
  analytics,
  languages;

  Widget icon(double size, BuildContext context) {
    switch (this) {
      case FreeModeOptions.chat:
        return Icon(
          Icons.chat_outlined,
          size: size,
          color: SubscriptionMode.free.borderColor(context),
        );
      case FreeModeOptions.create:
        return Icon(
          Icons.groups_outlined,
          size: size,
          color: SubscriptionMode.free.borderColor(context),
        );
      case FreeModeOptions.bot:
        return BotFace(
          expression: BotExpression.gold,
          width: size,
        );
      case FreeModeOptions.activities:
        return Icon(
          Icons.event_note_outlined,
          size: size,
          color: SubscriptionMode.free.borderColor(context),
        );
      case FreeModeOptions.analytics:
        return Icon(
          Symbols.monitoring,
          size: size,
          color: SubscriptionMode.free.borderColor(context),
        );
      case FreeModeOptions.languages:
        return Icon(
          Icons.language_outlined,
          size: size,
          color: SubscriptionMode.free.borderColor(context),
        );
    }
  }

  String description(L10n l10n) {
    switch (this) {
      case FreeModeOptions.chat:
        return l10n.freeModeChatDesc;
      case FreeModeOptions.create:
        return l10n.freeModeCreateDesc;
      case FreeModeOptions.bot:
        return l10n.freeModeBotDesc;
      case FreeModeOptions.activities:
        return l10n.freeModeActivitiesDesc;
      case FreeModeOptions.analytics:
        return l10n.freeModeAnalyticsDesc;
      case FreeModeOptions.languages:
        return l10n.freeModeLanguagesDesc;
    }
  }
}

enum PaidModeOptions {
  write,
  generate,
  analytics,
  audio,
  practice,
  emojis;

  Widget icon(double size, BuildContext context) {
    switch (this) {
      case PaidModeOptions.write:
        return Icon(
          Icons.edit_square,
          size: size,
          color: SubscriptionMode.paid.borderColor(context),
        );
      case PaidModeOptions.generate:
        return Icon(
          Icons.lightbulb_outlined,
          size: size,
          color: SubscriptionMode.paid.borderColor(context),
        );
      case PaidModeOptions.analytics:
        return Icon(
          Icons.star_outlined,
          size: size,
          color: SubscriptionMode.paid.borderColor(context),
        );
      case PaidModeOptions.audio:
        return Icon(
          Icons.volume_up_outlined,
          size: size,
          color: SubscriptionMode.paid.borderColor(context),
        );
      case PaidModeOptions.practice:
        return Icon(
          Icons.mic_outlined,
          size: size,
          color: SubscriptionMode.paid.borderColor(context),
        );
      case PaidModeOptions.emojis:
        return Icon(
          Icons.add_reaction_outlined,
          size: size,
          color: SubscriptionMode.paid.borderColor(context),
        );
    }
  }

  String description(L10n l10n) {
    switch (this) {
      case PaidModeOptions.write:
        return l10n.paidModeWriteDesc;
      case PaidModeOptions.generate:
        return l10n.paidModeGenerateDesc;
      case PaidModeOptions.analytics:
        return l10n.paidModeAnalyticsDesc;
      case PaidModeOptions.audio:
        return l10n.paidModeAudioDesc;
      case PaidModeOptions.practice:
        return l10n.paidModePracticeDesc;
      case PaidModeOptions.emojis:
        return l10n.paidModeEmojisDesc;
    }
  }
}

class SubscriptionModeDetails extends StatelessWidget {
  final SubscriptionMode mode;
  final Widget title;

  const SubscriptionModeDetails({
    super.key,
    required this.mode,
    required this.title,
  });

  Widget indicator(
    BuildContext context, {
    FreeModeOptions? freeOption,
    PaidModeOptions? paidOption,
  }) {
    if (freeOption == null && paidOption == null) {
      return const SizedBox.shrink();
    }

    final isColumnMode = FluffyThemes.isColumnMode(context);

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isColumnMode ? 24.0 : 8.0,
        vertical: 4.0,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 300,
        ),
        child: Row(
          spacing: isColumnMode ? 12.0 : 4.0,
          mainAxisSize: MainAxisSize.min,
          children: [
            freeOption?.icon(isColumnMode ? 40 : 24, context) ??
                paidOption!.icon(isColumnMode ? 40 : 24, context),
            Flexible(
              child: Text(
                freeOption?.description(L10n.of(context)) ??
                    paidOption!.description(L10n.of(context)),
                style: TextStyle(fontSize: isColumnMode ? 20 : 8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isColumnMode = FluffyThemes.isColumnMode(context);

    return Stack(
      children: [
        Container(
          margin: EdgeInsets.only(top: isColumnMode ? 14.0 : 8.0),
          padding: isColumnMode
              ? const EdgeInsets.all(12.0)
              : const EdgeInsets.symmetric(vertical: 12.0),
          decoration: BoxDecoration(
            border: Border.all(
              color: mode.borderColor(context),
              width: isColumnMode ? 4.0 : 1.0,
            ),
            borderRadius: BorderRadius.circular(24.0),
            color: theme.brightness == Brightness.light
                ? Colors.white
                : Colors.black,
          ),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.all(isColumnMode ? 24.0 : 4.0),
                child: title,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: indicator(
                      context,
                      freeOption: mode == SubscriptionMode.free
                          ? mode.options[0]
                          : null,
                      paidOption: mode == SubscriptionMode.paid
                          ? mode.options[0]
                          : null,
                    ),
                  ),
                  Flexible(
                    child: indicator(
                      context,
                      freeOption: mode == SubscriptionMode.free
                          ? mode.options[3]
                          : null,
                      paidOption: mode == SubscriptionMode.paid
                          ? mode.options[3]
                          : null,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: indicator(
                      context,
                      freeOption: mode == SubscriptionMode.free
                          ? mode.options[1]
                          : null,
                      paidOption: mode == SubscriptionMode.paid
                          ? mode.options[1]
                          : null,
                    ),
                  ),
                  Flexible(
                    child: indicator(
                      context,
                      freeOption: mode == SubscriptionMode.free
                          ? mode.options[4]
                          : null,
                      paidOption: mode == SubscriptionMode.paid
                          ? mode.options[4]
                          : null,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: indicator(
                      context,
                      freeOption: mode == SubscriptionMode.free
                          ? mode.options[2]
                          : null,
                      paidOption: mode == SubscriptionMode.paid
                          ? mode.options[2]
                          : null,
                    ),
                  ),
                  Flexible(
                    child: indicator(
                      context,
                      freeOption: mode == SubscriptionMode.free
                          ? mode.options[5]
                          : null,
                      paidOption: mode == SubscriptionMode.paid
                          ? mode.options[5]
                          : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Positioned(
          top: 0,
          left: isColumnMode ? 24.0 : 12.0,
          child: Container(
            decoration: BoxDecoration(
              color: mode.borderColor(context),
              borderRadius: BorderRadius.circular(40),
            ),
            padding:
                EdgeInsets.symmetric(horizontal: isColumnMode ? 12.0 : 8.0),
            child: Text(
              mode.label(L10n.of(context)),
              style: TextStyle(
                fontSize: isColumnMode ? 24 : 16,
                color: theme.colorScheme.surface,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
