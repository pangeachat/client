import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

class MultiPlatformAudioPlayer {
  final AudioPlayer audioPlayer;

  final Uint8List bytes;
  final String name;
  final String mimeType;

  const MultiPlatformAudioPlayer({
    required this.audioPlayer,
    required this.bytes,
    required this.name,
    required this.mimeType,
  });

  /// Plays to the end, and reports WHETHER it reached the end.
  ///
  /// The return value is not decoration. `AudioPlayer.play()` resolves when
  /// playback "completes or is paused or stopped", and the wait below also
  /// resolves on `idle`, which is where `stop()` puts the player — so a
  /// caller that treats a normal return as "the audio finished" is wrong every
  /// time something interrupts it. `true` only for a real completion.
  Future<bool> play() async {
    await audioPlayer.play();
    final state = await audioPlayer.processingStateStream.firstWhere(
      (state) =>
          state == ProcessingState.completed || state == ProcessingState.idle,
      orElse: () => ProcessingState.idle,
    );
    return state == ProcessingState.completed;
  }

  Future<bool> setAudioSourceAndPlay() async {
    await setAudioSource();
    return play();
  }

  Future<void> setAudioSource() async {
    kIsWeb ? await _setAudioSourceOnWeb() : await _setAudioSourceOnMobile();
  }

  Future<void> _setAudioSourceOnWeb() async {
    await audioPlayer.setAudioSource(
      AudioSource.uri(Uri.dataFromBytes(bytes, mimeType: mimeType)),
    );
  }

  Future<void> _setAudioSourceOnMobile() async {
    final file = await _generateAudioFile();
    audioPlayer.setFilePath(file.path);
  }

  Future<File> _generateAudioFile() async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$name');
    await file.writeAsBytes(bytes);
    return file;
  }
}
