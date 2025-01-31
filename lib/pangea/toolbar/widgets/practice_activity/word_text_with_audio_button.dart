import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/toolbar/controllers/tts_controller.dart';

class WordTextWithAudioButton extends StatefulWidget {
  final String text;
  final TtsController ttsController;
  final String eventID;

  const WordTextWithAudioButton({
    super.key,
    required this.text,
    required this.ttsController,
    required this.eventID,
  });

  @override
  WordAudioButtonState createState() => WordAudioButtonState();
}

class WordAudioButtonState extends State<WordTextWithAudioButton> {
  bool _isPlaying = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (event) => setState(() {}),
      onExit: (event) => setState(() {}),
      child: GestureDetector(
        onTap: () async {
          if (_isPlaying) {
            await widget.ttsController.stop();
            if (mounted) {
              setState(() => _isPlaying = false);
            }
          } else {
            if (mounted) {
              setState(() => _isPlaying = true);
            }
            try {
              await widget.ttsController.tryToSpeak(
                widget.text,
                context,
                widget.eventID,
              );
            } catch (e, s) {
              ErrorHandler.logError(
                e: e,
                s: s,
                data: {
                  "text": widget.text,
                  "eventID": widget.eventID,
                },
              );
            } finally {
              if (mounted) {
                setState(() => _isPlaying = false);
              }
            }
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  widget.text,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _isPlaying
                            ? Theme.of(context).colorScheme.secondary
                            : null,
                        fontSize:
                            Theme.of(context).textTheme.titleLarge?.fontSize,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                _isPlaying ? Icons.play_arrow : Icons.play_arrow_outlined,
                size: Theme.of(context).textTheme.titleLarge?.fontSize,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
