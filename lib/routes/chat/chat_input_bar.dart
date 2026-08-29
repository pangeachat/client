import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/routes/chat/chat.dart';
import 'package:fluffychat/routes/chat/chat_emoji_picker.dart';
import 'package:fluffychat/routes/chat/degradation_banner.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/streaming_stt_gate.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/streaming_stt_session.dart';
import 'package:fluffychat/routes/chat/keyboard_prompt_banner.dart';
import 'package:fluffychat/routes/chat/pangea_chat_input_row.dart';
import 'package:fluffychat/routes/chat/recording_view_model.dart';
import 'package:fluffychat/routes/chat/reply_display.dart';
import 'package:fluffychat/widgets/matrix.dart';

class ChatInputBar extends StatelessWidget {
  final ChatController controller;
  final double padding;

  const ChatInputBar({
    required this.controller,
    required this.padding,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The streaming-STT session factory + D11 language gate, lifted here (from
    // PangeaChatInputRow) so the RecordingViewModel this creates can sit ABOVE
    // the composer's Material box below: the degradation banner then renders
    // as a SIBLING above that box instead of inside it, where the box's
    // Clip.hardEdge was cutting off the banner's shadow. This is the single
    // source of truth for recording state — passed down into
    // PangeaChatInputRow, never duplicated.
    final activel2 = controller.pangeaController.userController.userL2;
    final streamingSessionFactory = buildStreamingSessionFactory(
      flagEnabled: Environment.liveStreamingSttEnabled,
      messageLangCodeShort: activel2?.langCodeShort,
      accessToken: Matrix.of(context).client.accessToken,
      wsUrl: PApiUrls.speechToTextStream,
    );
    final languageUnsupportedForStreaming =
        StreamingSttGate.languageUnsupported(
          flagEnabled: Environment.liveStreamingSttEnabled,
          messageLangCodeShort: activel2?.langCodeShort,
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: EdgeInsets.all(
            FluffyThemes.isColumnMode(context) ? 16.0 : 8.0,
          ),
          constraints: const BoxConstraints(
            maxWidth: FluffyThemes.maxTimelineWidth,
          ),
          alignment: Alignment.center,
          // Branch on abandoned-DM BEFORE creating the RecordingViewModel: an
          // abandoned room has no composer/recorder, and if a room goes abandoned
          // mid-recording the VM must leave the tree so its state disposes and
          // tears down the active recorder/socket. Wrapping the VM around this
          // branch would keep it mounted and leak the capture path.
          child: controller.room.isAbandonedDMRoom == true
              ? Material(
                  clipBehavior: Clip.hardEdge,
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: const BorderRadius.all(Radius.circular(24)),
                  child: _AbandonedDMContent(controller: controller),
                )
              : RecordingViewModel(
                  streamingSessionFactory: streamingSessionFactory,
                  languageUnsupportedForStreaming:
                      languageUnsupportedForStreaming,
                  builder: (context, recordingViewModel) {
                    final bannerKind = recordingViewModel.degradationBanner;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Both banners float ABOVE the composer box (sibling),
                        // so the box's Clip.hardEdge never cuts their shadow.
                        KeyboardPromptBanner(
                          composerFocusNode: controller.inputFocus,
                          targetLanguageCode: () => controller
                              .pangeaController
                              .userController
                              .userL2Code,
                        ),
                        if (bannerKind != DegradationBannerKind.none)
                          DegradationBanner(
                            kind: bannerKind,
                            onDismiss:
                                recordingViewModel.dismissDegradationBanner,
                          ),
                        Material(
                          clipBehavior: Clip.hardEdge,
                          color: theme.colorScheme.surfaceContainerHigh,
                          borderRadius: const BorderRadius.all(
                            Radius.circular(24),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ReplyDisplay(controller),
                              PangeaChatInputRow(
                                controller: controller,
                                recordingViewModel: recordingViewModel,
                              ),
                              ChatEmojiPicker(controller),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _AbandonedDMContent extends StatelessWidget {
  final ChatController controller;

  const _AbandonedDMContent({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        TextButton.icon(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.all(16),
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          icon: const Icon(Icons.archive_outlined),
          onPressed: controller.leaveChat,
          label: Text(L10n.of(context).leave),
        ),
        TextButton.icon(
          style: TextButton.styleFrom(padding: const EdgeInsets.all(16)),
          icon: const Icon(Icons.forum_outlined),
          onPressed: controller.recreateChat,
          label: Text(L10n.of(context).reopenChat),
        ),
      ],
    );
  }
}
