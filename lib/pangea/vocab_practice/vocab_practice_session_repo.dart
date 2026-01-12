import 'dart:math';

import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';
import 'package:fluffychat/pangea/vocab_practice/vocab_practice_session_model.dart';
import 'package:fluffychat/widgets/matrix.dart';

class VocabPracticeSessionRepo {
  static final GetStorage _storage = GetStorage('vocab_practice_session');

  static Future<VocabPracticeSessionModel> get currentSession async {
    final cached = _getCached();
    if (cached != null) {
      return cached;
    }

    final r = Random();
    final activityTypes = [
      ActivityTypeEnum.lemmaMeaning,
      //ActivityTypeEnum.lemmaAudio,
    ];

    final types = List.generate(
      VocabPracticeSessionModel.practiceGroupSize,
      (_) => activityTypes[r.nextInt(activityTypes.length)],
    );

    final targets = await _fetch();
    final session = VocabPracticeSessionModel(
      userL1: MatrixState.pangeaController.userController.userL1!.langCode,
      userL2: MatrixState.pangeaController.userController.userL2!.langCode,
      startedAt: DateTime.now(),
      sortedConstructIds: targets,
      activityTypes: types,
      completedUses: [],
    );
    await _setCached(session);
    return session;
  }

  static Future<void> updateSession(
    VocabPracticeSessionModel session,
  ) =>
      _setCached(session);

  static Future<VocabPracticeSessionModel> reloadSession() async {
    _storage.erase();
    return currentSession;
  }

  static Future<void> clearSession() => _storage.erase();

  static Future<List<ConstructIdentifier>> _fetch() async {
    final constructs = await MatrixState
        .pangeaController.matrixState.analyticsDataService
        .getAggregatedConstructs(ConstructTypeEnum.vocab)
        .then((map) => map.values.toList());

    // maintain a Map of ConstructIDs to last use dates and a sorted list of ConstructIDs
    // based on last use. Update the map / list on practice completion
    final Map<ConstructIdentifier, DateTime?> constructLastUseMap = {};
    final List<ConstructIdentifier> sortedTargetIds = [];
    for (final construct in constructs) {
      constructLastUseMap[construct.id] = construct.lastUsed;
      sortedTargetIds.add(construct.id);
    }

    sortedTargetIds.sort((a, b) {
      final dateA = constructLastUseMap[a];
      final dateB = constructLastUseMap[b];
      if (dateA == null && dateB == null) return 0;
      if (dateA == null) return -1;
      if (dateB == null) return 1;
      return dateA.compareTo(dateB);
    });

    return sortedTargetIds;
  }

  static VocabPracticeSessionModel? _getCached() {
    final keys = List<String>.from(_storage.getKeys());
    if (keys.isEmpty) return null;
    try {
      final json = _storage.read(keys.first) as Map<String, dynamic>;
      return VocabPracticeSessionModel.fromJson(json);
    } catch (e) {
      _storage.remove(keys.first);
      return null;
    }
  }

  static Future<void> _setCached(VocabPracticeSessionModel session) async {
    await _storage.erase();
    await _storage.write(
      session.startedAt.toIso8601String(),
      session.toJson(),
    );
  }
}
