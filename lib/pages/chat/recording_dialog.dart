import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:path/path.dart' as path_lib;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'events/audio_player.dart';

class PermissionException implements Exception {}

class EmptyAudioException implements Exception {}

class RecordingDialog extends StatefulWidget {
  const RecordingDialog({
    super.key,
  });

  @override
  RecordingDialogState createState() => RecordingDialogState();
}

class RecordingDialogState extends State<RecordingDialog> {
  Timer? _recorderSubscription;
  Duration _duration = Duration.zero;

  // #Pangea
  // bool error = false;
  Object? error;
  bool _loading = true;
  // Pangea#

  final _audioRecorder = AudioRecorder();
  final List<double> amplitudeTimeline = [];

  String? fileName;

  Future<void> startRecording() async {
    final store = Matrix.of(context).store;
    try {
      // #Pangea
      // final codec = kIsWeb
      //     // Web seems to create webm instead of ogg when using opus encoder
      //     // which does not play on iOS right now. So we use wav for now:
      //     ? AudioEncoder.wav
      //     // Everywhere else we use opus if supported by the platform:
      //     : await _audioRecorder.isEncoderSupported(AudioEncoder.opus)
      //         ? AudioEncoder.opus
      //         : AudioEncoder.aacLc;
      const codec = AudioEncoder.wav;
      // Pangea#
      fileName =
          'recording${DateTime.now().microsecondsSinceEpoch}.${codec.fileExtension}';
      String? path;
      if (!kIsWeb) {
        final tempDir = await getTemporaryDirectory();
        path = path_lib.join(tempDir.path, fileName);
      }

      final result = await _audioRecorder.hasPermission();
      if (result != true) {
        // #Pangea
        throw PermissionException();
        // setState(() => error = true);
        // return;
        // Pangea#
      }
      await WakelockPlus.enable();

      await _audioRecorder.start(
        RecordConfig(
          bitRate: AppSettings.audioRecordingBitRate.getItem(store),
          sampleRate: AppSettings.audioRecordingSamplingRate.getItem(store),
          numChannels: AppSettings.audioRecordingNumChannels.getItem(store),
          autoGain: AppSettings.audioRecordingAutoGain.getItem(store),
          echoCancel: AppSettings.audioRecordingEchoCancel.getItem(store),
          noiseSuppress: AppSettings.audioRecordingNoiseSuppress.getItem(store),
          encoder: codec,
        ),
        path: path ?? '',
      );

      // #Pangea
      // setState(() => _duration = Duration.zero);
      setState(() {
        _duration = Duration.zero;
        _loading = false;
      });
      // Pangea#
      _recorderSubscription?.cancel();
      _recorderSubscription =
          Timer.periodic(const Duration(milliseconds: 100), (_) async {
        final amplitude = await _audioRecorder.getAmplitude();
        var value = 100 + amplitude.current * 2;
        value = value < 1 ? 1 : value;
        amplitudeTimeline.add(value);
        setState(() {
          _duration += const Duration(milliseconds: 100);
        });
      });
      // #Pangea
      // } catch (_) {
      //   setState(() => error = true);
    } catch (e) {
      setState(() => error = e);
      // Pangea#
      rethrow;
    }
  }

  @override
  void initState() {
    super.initState();
    startRecording();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _recorderSubscription?.cancel();
    _audioRecorder.stop();
    super.dispose();
  }

  void _stopAndSend() async {
    _recorderSubscription?.cancel();
    final path = await _audioRecorder.stop();

    if (path == null) throw ('Recording failed!');
    const waveCount = AudioPlayerWidget.wavesCount;
    final step = amplitudeTimeline.length < waveCount
        ? 1
        : (amplitudeTimeline.length / waveCount).round();
    final waveform = <int>[];
    for (var i = 0; i < amplitudeTimeline.length; i += step) {
      waveform.add((amplitudeTimeline[i] / 100 * 1024).round());
    }

    // #Pangea
    if (amplitudeTimeline.isEmpty || amplitudeTimeline.every((e) => e <= 1)) {
      if (mounted) {
        setState(() => error = EmptyAudioException());
      }
      return;
    }
    // Pangea#

    Navigator.of(context, rootNavigator: false).pop<RecordingResult>(
      RecordingResult(
        path: path,
        duration: _duration.inMilliseconds,
        waveform: waveform,
        fileName: fileName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    const maxDecibalWidth = 64.0;
    final time =
        '${_duration.inMinutes.toString().padLeft(2, '0')}:${(_duration.inSeconds % 60).toString().padLeft(2, '0')}';
    // #Pangea
    // final content = error
    //     ? Text(L10n.of(context).oopsSomethingWentWrong)
    final content = error != null
        ? ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 250.0),
            child: error is PermissionException
                ? Text(L10n.of(context).recordingPermissionDenied)
                : kIsWeb && error is! EmptyAudioException
                    ? Text(L10n.of(context).genericWebRecordingError)
                    : Text(error!.toLocalizedString(context)),
          )
        // Pangea#
        : Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(32),
                  color: Colors.red,
                ),
              ),
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: amplitudeTimeline.reversed
                      .take(26)
                      .toList()
                      .reversed
                      .map(
                        (amplitude) => Container(
                          margin: const EdgeInsets.only(left: 2),
                          width: 4,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius:
                                BorderRadius.circular(AppConfig.borderRadius),
                          ),
                          height: maxDecibalWidth * (amplitude / 100),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 48,
                // #Pangea
                // child: Text(time),
                child: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator.adaptive(),
                      )
                    : Text(time),
                // Pangea#
              ),
            ],
          );
    if (PlatformInfos.isCupertinoStyle) {
      return CupertinoAlertDialog(
        content: content,
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context, rootNavigator: false).pop(),
            child: Text(
              L10n.of(context).cancel,
              style: TextStyle(
                color: theme.textTheme.bodyMedium?.color?.withAlpha(150),
              ),
            ),
          ),
          // #Pangea
          // if (error != true)
          if (error == null)
            // Pangea#
            CupertinoDialogAction(
              onPressed: _stopAndSend,
              child: Text(L10n.of(context).send),
            ),
        ],
      );
    }
    return AlertDialog(
      content: content,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: false).pop(),
          child: Text(
            L10n.of(context).cancel,
            style: TextStyle(
              color: theme.colorScheme.error,
            ),
          ),
        ),
        // #Pangea
        // if (error != true)
        if (error == null)
          // Pangea#
          TextButton(
            onPressed: _stopAndSend,
            child: Text(L10n.of(context).send),
          ),
      ],
    );
  }
}

class RecordingResult {
  final String path;
  final int duration;
  final List<int> waveform;
  final String? fileName;

  const RecordingResult({
    required this.path,
    required this.duration,
    required this.waveform,
    required this.fileName,
  });
}

extension on AudioEncoder {
  String get fileExtension {
    switch (this) {
      case AudioEncoder.aacLc:
      case AudioEncoder.aacEld:
      case AudioEncoder.aacHe:
        return 'm4a';
      case AudioEncoder.opus:
        return 'ogg';
      case AudioEncoder.wav:
        return 'wav';
      case AudioEncoder.amrNb:
      case AudioEncoder.amrWb:
      case AudioEncoder.flac:
      case AudioEncoder.pcm16bits:
        throw UnsupportedError('Not yet used');
    }
  }
}
