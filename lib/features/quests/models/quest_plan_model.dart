import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/features/quests/models/learning_objective_model.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';

/// A v3 Quest, read from the CMS `quest-plans` collection: an ordered sequence
/// of Learning Objectives (Missions) a learner advances through.
///
/// Read canonical. Localization of `name`/`description` is choreo's concern,
/// consumed later when these reads swap to choreo endpoints.
class QuestPlan {
  final String id;
  final String name;
  final String description;

  /// Target language (L2) the quest teaches.
  final String targetLanguage;
  final String? targetL1;
  final String? targetCefr;

  final List<QuestObjectiveStep> sequence;

  /// The MXID of whoever made this course — the person credited on every
  /// surface that shows it (`ContentCreatorChip`). Read verbatim from the
  /// quest-plans row's plain-text `owner_mxid`, deliberately NOT the `owner`
  /// relationship beside it: a relationship is a per-environment matrix-users
  /// row id the client cannot resolve (`matrix-users` reads are service- and
  /// admin-only), so the MXID is stored where the consumer reads it and no
  /// service resolves the owner on the client's behalf.
  ///
  /// Null where no owner is recorded. Null is NOT `@system:pangea.chat`:
  /// crediting an unknown owner to Pangea would misattribute a teacher's
  /// course, so display surfaces show no credit rather than a guessed one.
  final String? ownerId;

  const QuestPlan({
    required this.id,
    required this.name,
    required this.description,
    required this.targetLanguage,
    this.targetL1,
    this.targetCefr,
    required this.sequence,
    this.ownerId,
  });

  List<String> get learningObjectiveIds =>
      sequence.map((step) => step.objective.id).toList();

  /// Display forms of the quest's two header fields, mirroring
  /// `CoursePlanModel.targetLanguageDisplay` and `CoursePlanModel.cefrLevel` —
  /// the same chips render off either model, so they must read identically.
  String get targetLanguageDisplay =>
      PLanguageStore.byLangCode(targetLanguage)?.langCode.toUpperCase() ??
      targetLanguage.toUpperCase();

  String get targetLanguageFullDisplay =>
      PLanguageStore.byLangCode(targetLanguage)?.displayName ??
      targetLanguageDisplay;

  LanguageLevelTypeEnum get cefrLevel =>
      LanguageLevelTypeEnum.fromString(targetCefr);

  factory QuestPlan.fromJson(Map<String, dynamic> json) {
    final res = (json['res'] as Map?)?.cast<String, dynamic>() ?? const {};
    final req = (json['req'] as Map?)?.cast<String, dynamic>() ?? const {};
    final rawSeq = (res['learning_objective_sequence'] as List?) ?? const [];
    return QuestPlan(
      id: json['id'] as String,
      name: (res['name'] ?? '') as String,
      description: (res['description'] ?? '') as String,
      targetLanguage: (req['target_language'] ?? '') as String,
      targetL1: req['target_l1'] as String?,
      targetCefr: req['target_cefr'] as String?,
      sequence: rawSeq
          .map(
            (e) =>
                QuestObjectiveStep.fromJson((e as Map).cast<String, dynamic>()),
          )
          .toList(),
      ownerId: json['owner_mxid'] as String?,
    );
  }
}

/// One step in a quest: a Learning Objective plus whether it was newly minted
/// for this quest (vs recycled from the catalog).
class QuestObjectiveStep {
  final LearningObjective objective;
  final bool wasMinted;

  const QuestObjectiveStep({required this.objective, required this.wasMinted});

  factory QuestObjectiveStep.fromJson(Map<String, dynamic> json) {
    // `learning_objective` is a populated object at depth>=1, or a bare id
    // string at depth 0.
    final lo = json['learning_objective'];
    final objective = lo is Map
        ? LearningObjective.fromJson(lo.cast<String, dynamic>())
        : LearningObjective(id: lo as String, objective: '');
    return QuestObjectiveStep(
      objective: objective,
      wasMinted: json['was_minted'] == true,
    );
  }
}
