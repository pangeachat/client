import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_misc/analytics_constants.dart';
import 'package:fluffychat/pangea/chat/widgets/chat_banner_builder.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';

class LevelUpConstants {
  static const String starFileName = "star.png";
  static const String dinoLevelUPFileName = "DinoBot-Congratulate.png";
}

class LevelUpBanner extends StatefulWidget {
  final int level;
  final int prevLevel;
  final String overlayKey;
  final Completer<void> closeCompleter;

  const LevelUpBanner({
    required this.level,
    required this.prevLevel,
    required this.overlayKey,
    required this.closeCompleter,
    super.key,
  });

  @override
  State<LevelUpBanner> createState() => _LevelUpBannerState();
}

class _LevelUpBannerState extends State<LevelUpBanner> {
  @override
  void initState() {
    super.initState();
    _playLevelUpSound();
  }

  Future<void> _playLevelUpSound() async {
    final player = AudioPlayer();
    try {
      player.setVolume(min(0.05, AppSettings.volume.value));
      await player.play(
        UrlSource(
          "${AppConfig.assetsBaseURL}/${AnalyticsConstants.levelUpAudioFileName}",
        ),
      );
      await Future.delayed(const Duration(seconds: 2));
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {"message": "Failed to play level up sound"},
      );
    } finally {
      await player.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isColumnMode = FluffyThemes.isColumnMode(context);

    final style = isColumnMode
        ? Theme.of(context).textTheme.titleLarge?.copyWith(
            color: AppConfig.gold,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          )
        : Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: AppConfig.gold,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          );

    return ChatBannerBuilder(
      overlayKey: widget.overlayKey,
      closeCompleter: widget.closeCompleter,
      builder: (context, constraints, close) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SizedBox(width: constraints.maxWidth >= 600 ? 120.0 : 65.0),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isColumnMode ? 16.0 : 8.0,
              ),
              child: Wrap(
                spacing: 16.0,
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    L10n.of(context).levelUp,
                    style: style,
                    overflow: TextOverflow.ellipsis,
                  ),
                  CachedNetworkImage(
                    imageUrl:
                        "${AppConfig.assetsBaseURL}/${LevelUpConstants.starFileName}",
                    height: 24,
                    width: 24,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: constraints.maxWidth >= 600 ? 120.0 : 65.0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SizedBox(
                  width: 32.0,
                  height: 32.0,
                  child: Tooltip(
                    message: L10n.of(context).close,
                    child: IconButton(
                      icon: const Icon(Icons.close),
                      style: IconButton.styleFrom(
                        padding: const EdgeInsets.all(4.0),
                      ),
                      onPressed: close,
                      constraints: const BoxConstraints(),
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
