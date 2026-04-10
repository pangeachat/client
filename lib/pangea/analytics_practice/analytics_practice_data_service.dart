import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_repo.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_exercise_model.dart';
import 'package:fluffychat/pangea/toolbar/message_practice/message_audio_card.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class AnalyticsPracticeChoice {
  final String choiceId;
  final String choiceText;
  final String? choiceEmoji;

  const AnalyticsPracticeChoice({
    required this.choiceId,
    required this.choiceText,
    this.choiceEmoji,
  });
}

class AnalyticsPracticeDataService {
  final Map<String, Map<String, String>> _choiceTexts = {};
  final Map<String, Map<String, String?>> _choiceEmojis = {};
  final Map<String, PangeaAudioFile> _audioFiles = {};
  final Map<String, String> _audioTranslations = {};

  void clear() {
    _choiceTexts.clear();
    _choiceEmojis.clear();
    _audioFiles.clear();
    _audioTranslations.clear();
  }

  String _getChoiceText(String key, String choiceId, ConstructTypeEnum type) {
    if (type == ConstructTypeEnum.morph) {
      return choiceId;
    }
    if (_choiceTexts.containsKey(key) &&
        _choiceTexts[key]!.containsKey(choiceId)) {
      return _choiceTexts[key]![choiceId]!;
    }
    final cId = ConstructIdentifier.fromString(choiceId);
    return cId?.lemma ?? choiceId;
  }

  String? _getChoiceEmoji(String key, String choiceId, ConstructTypeEnum type) {
    if (type == ConstructTypeEnum.morph) return null;
    return _choiceEmojis[key]?[choiceId];
  }

  PangeaAudioFile? getAudioFile(MultipleChoicePracticeExerciseModel exercise) {
    if (exercise is! VocabAudioPracticeExerciseModel) return null;
    if (exercise.eventId == null) return null;
    return _audioFiles[exercise.eventId];
  }

  String? getAudioTranslation(MultipleChoicePracticeExerciseModel exercise) {
    if (exercise is! VocabAudioPracticeExerciseModel) return null;
    if (exercise.eventId == null) return null;
    final translation = _audioTranslations[exercise.eventId];
    return translation;
  }

  List<AnalyticsPracticeChoice> filteredChoices(
    MultipleChoicePracticeExerciseModel exercise,
    ConstructTypeEnum type,
  ) {
    final content = exercise.multipleChoiceContent;
    final choices = content.choices.toList();
    final answer = content.answers.first;
    final filtered = <AnalyticsPracticeChoice>[];

    final seenTexts = <String>{};
    for (final id in choices) {
      final text = _getChoiceText(exercise.storageKey, id, type);

      if (seenTexts.contains(text)) {
        if (id != answer) {
          continue;
        }

        final index = filtered.indexWhere(
          (choice) => choice.choiceText == text,
        );
        if (index != -1) {
          filtered[index] = AnalyticsPracticeChoice(
            choiceId: id,
            choiceText: text,
            choiceEmoji: _getChoiceEmoji(exercise.storageKey, id, type),
          );
        }
        continue;
      }

      seenTexts.add(text);
      filtered.add(
        AnalyticsPracticeChoice(
          choiceId: id,
          choiceText: text,
          choiceEmoji: _getChoiceEmoji(exercise.storageKey, id, type),
        ),
      );
    }

    return filtered;
  }

  void _setLemmaInfo(
    String requestKey,
    Map<String, String> texts,
    Map<String, String?> emojis,
  ) {
    _choiceTexts.putIfAbsent(requestKey, () => {});
    _choiceEmojis.putIfAbsent(requestKey, () => {});

    _choiceTexts[requestKey]!.addAll(texts);
    _choiceEmojis[requestKey]!.addAll(emojis);
  }

  void _setAudioInfo(
    String eventId,
    PangeaAudioFile audioFile,
    String translation,
  ) {
    _audioFiles[eventId] = audioFile;
    _audioTranslations[eventId] = translation;
  }

  Future<void> prefetchExerciseInfo(
    MultipleChoicePracticeExerciseModel exercise,
  ) async {
    // Prefetch lemma info for meaning activities before marking ready
    if (exercise is VocabMeaningPracticeExerciseModel) {
      final choices = exercise.multipleChoiceContent.choices.toList();
      await _prefetchLemmaInfo(exercise.storageKey, choices);
    }

    // Prefetch audio for audio activities before marking ready
    if (exercise is VocabAudioPracticeExerciseModel) {
      await _prefetchAudioInfo(exercise);
    }
  }

  Future<void> _prefetchAudioInfo(
    VocabAudioPracticeExerciseModel exercise,
  ) async {
    final eventId = exercise.eventId;
    final roomId = exercise.roomId;
    if (eventId == null || roomId == null) {
      throw Exception("Missing eventId or roomId in _prefetchAudioInfo");
    }

    final client = MatrixState.pangeaController.matrixState.client;
    final room = client.getRoomById(roomId);

    if (room == null) {
      throw Exception("Room not found in _prefetchAudioInfo");
    }

    final event = await room.getEventById(eventId);
    if (event == null) {
      throw Exception("Event not found in _prefetchAudioInfo");
    }

    final pangeaEvent = PangeaMessageEvent(
      event: event,
      timeline: await room.getTimeline(),
      ownMessage: event.senderId == client.userID,
    );

    final tokens = pangeaEvent.originalSent?.tokens;
    if (tokens == null || tokens.length > 25) {
      throw Exception("Too many tokens in _prefetchAudioInfo");
    }

    // Prefetch the audio file
    final audioFile = await pangeaEvent.requestTextToSpeech(
      exercise.langCode,
      MatrixState.pangeaController.userController.voice,
    );

    if (audioFile.duration == null || audioFile.duration! <= 2000) {
      throw Exception("Audio file too short");
    }

    // Prefetch the translation
    final translation = await pangeaEvent.requestTranslationByL1();
    _setAudioInfo(eventId, audioFile, translation.bestTranslation);
  }

  Future<void> _prefetchLemmaInfo(
    String requestKey,
    List<String> choiceIds,
  ) async {
    final texts = <String, String>{};
    final emojis = <String, String?>{};

    for (final id in choiceIds) {
      final cId = ConstructIdentifier.fromString(id);
      if (cId == null) continue;

      final res = await cId.getLemmaInfo({});
      if (res.isError) {
        LemmaInfoRepo.clearCache(cId.lemmaInfoRequest({}));
        throw Exception("Failed to fetch lemma info for id $id");
      }

      texts[id] = res.result!.meaning;
      emojis[id] = res.result!.emoji.firstOrNull;
    }

    _setLemmaInfo(requestKey, texts, emojis);
  }
}
