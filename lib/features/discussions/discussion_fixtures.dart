import 'dart:convert';

import 'package:flutter/services.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/discussions/discussion_extensions.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';

/// One dummy discussion from the prototype's local file (#9647): 3 to 4
/// questions about its one photo.
class DiscussionFixture {
  final String id;
  final List<String> questions;

  /// A short umbrella question in the target language, framing the whole
  /// discussion: the card's and the room's title. Falls back to the first
  /// question.
  final String? _title;
  final String? courseRoomId;
  final String? l2;
  final String? loId;

  /// 1-based position in the course plan, for an entry that names no [loId].
  final int? missionNumber;
  final String? imageUrl;

  /// `[lng, lat]`, as activities store them.
  final List<double>? coordinates;

  const DiscussionFixture({
    required this.id,
    required this.questions,
    String? title,
    this.courseRoomId,
    this.l2,
    this.loId,
    this.missionNumber,
    this.imageUrl,
    this.coordinates,
  }) : _title = title;

  /// What its card and room are titled.
  String get title => _title ?? questions.first;

  /// A pool entry (no [loId], no [missionNumber]) placed in Mission [n] of
  /// a course: its own id there, so the same entry in two Missions is two
  /// discussions with two sets of rooms.
  DiscussionFixture inMission(int n) => DiscussionFixture(
    id: '$id-m$n',
    questions: questions,
    title: _title,
    courseRoomId: courseRoomId,
    l2: l2,
    imageUrl: imageUrl,
    coordinates: coordinates,
  );

  bool get isPooled => loId == null && missionNumber == null;

  /// The id it travels under wherever activities are keyed by id.
  String get activityId => '${DiscussionIds.prefix}$id';

  static DiscussionFixture? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final raw = json['questions'];
    final questions = [
      if (raw is List) ...raw.whereType<String>(),
      if (json['question'] is String) json['question'] as String,
    ];
    if (id is! String || id.isEmpty || questions.isEmpty) return null;
    final coords = json['coordinates'];
    return DiscussionFixture(
      id: id,
      questions: questions,
      title: json['title'] as String?,
      courseRoomId: json['course_room_id'] as String?,
      l2: json['l2'] as String?,
      loId: json['lo_id'] as String?,
      missionNumber: (json['mission_number'] as num?)?.toInt(),
      imageUrl: json['image_url'] as String?,
      coordinates: coords is List && coords.length == 2
          ? coords.map((e) => (e as num).toDouble()).toList()
          : null,
    );
  }

  /// The Mission this entry sits in, in a plan whose Missions run
  /// [orderedLoIds]; null when it names none the plan has.
  String? missionIn(List<String> orderedLoIds) {
    final loId = this.loId;
    if (loId != null) return orderedLoIds.contains(loId) ? loId : null;
    final n = missionNumber;
    if (n == null || n < 1 || n > orderedLoIds.length) return null;
    return orderedLoIds[n - 1];
  }

  bool appliesTo({required String? courseRoomId, required String l2}) {
    final course = this.courseRoomId;
    if (course != null && course != courseRoomId) return false;
    final lang = this.l2;
    return lang == null || lang.split('-').first == l2.split('-').first;
  }
}

/// The prototype's stand-in for course-owned discussion rows (#9647): a local
/// file merged into a course's listing, so discussions reach the Mission card
/// and the course map the way real rows will. Read on staging builds only;
/// production never sees it.
class DiscussionFixtures {
  const DiscussionFixtures._();

  static const String assetPath = 'assets/pangea/discussions_dummy.json';

  static bool get enabled =>
      Environment.activeEnvironment == Environment.staging;

  static Future<List<DiscussionFixture>>? _loading;

  /// Every plan built so far, by activity id, so a read by id (the map's
  /// large card) finds the same plan the course listing showed.
  static final Map<String, ActivityPlanModel> _plans = {};

  static ActivityPlanModel? planFor(String activityId) => _plans[activityId];

  /// Every discussion's questions, by activity id, once the file is read.
  static final Map<String, List<String>> _questions = {};

  /// [activityId]'s questions, in order; empty before the file is read.
  static List<String> questionsFor(String activityId) =>
      _questions[activityId] ?? const [];

  static Future<List<DiscussionFixture>> load() {
    if (!enabled) return Future.value(const []);
    return _loading ??= _read();
  }

  static Future<List<DiscussionFixture>> _read() async {
    try {
      final raw = jsonDecode(await rootBundle.loadString(assetPath));
      final list = raw is Map ? raw['discussions'] : null;
      if (list is! List) throw const FormatException('no discussions list');
      final fixtures = [
        for (final e in list)
          if (e is Map) ?DiscussionFixture.fromJson(e.cast<String, dynamic>()),
      ];
      for (final f in fixtures) {
        _questions[f.activityId] = f.questions;
      }
      return fixtures;
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {'asset': assetPath});
      return const [];
    }
  }

  /// Which discussions sit in each of a course's Missions ([loIds], in plan
  /// order): the entries that name a Mission, then — so every Mission has at
  /// least one — the pool entries, handed in turn to each Mission still
  /// without one.
  static Map<String, List<DiscussionFixture>> _assign(
    List<DiscussionFixture> fixtures, {
    required String? courseRoomId,
    required String l2,
    required List<String> loIds,
  }) {
    final byLo = <String, List<DiscussionFixture>>{};
    final pool = <DiscussionFixture>[];
    for (final f in fixtures) {
      if (!f.appliesTo(courseRoomId: courseRoomId, l2: l2)) continue;
      if (f.isPooled) {
        pool.add(f);
        continue;
      }
      final loId = f.missionIn(loIds);
      if (loId != null) (byLo[loId] ??= []).add(f);
    }
    if (pool.isEmpty) return byLo;
    var next = 0;
    for (final (i, loId) in loIds.indexed) {
      if (byLo[loId]?.isNotEmpty ?? false) continue;
      final placed = pool[next++ % pool.length].inMission(i + 1);
      _questions[placed.activityId] = placed.questions;
      byLo[loId] = [placed];
    }
    return byLo;
  }

  /// [outline]'s groups with the course's discussions added at the end of
  /// their Missions.
  static Future<QuestOutline> addTo(
    QuestOutline outline, {
    required String? courseRoomId,
  }) async {
    final fixtures = await load();
    if (fixtures.isEmpty) return outline;
    final quest = outline.quest;
    final byLo = _assign(
      fixtures,
      courseRoomId: courseRoomId,
      l2: quest.targetLanguage,
      loIds: quest.learningObjectiveIds,
    );
    if (byLo.isEmpty) return outline;
    return outline.withCourse(
      groups: [
        for (final group in outline.groups)
          QuestObjectiveGroup(
            objective: group.objective,
            activities: [
              ...group.activities,
              for (final (i, f)
                  in (byLo[group.objective.id] ?? const []).indexed)
                QuestActivity(
                  activityId: f.activityId,
                  plan: _buildPlan(f, group, quest.targetLanguage, i),
                ),
            ],
            pacing: group.pacing,
            credit: group.credit,
            hiddenActivities: group.hiddenActivities,
          ),
      ],
    );
  }

  static ActivityPlanModel _buildPlan(
    DiscussionFixture f,
    QuestObjectiveGroup group,
    String l2,
    int index,
  ) {
    // An activity of the Mission lends its photo when the entry names none,
    // and its suggested vocab: the Mission's [index]th discussion borrows
    // from its [index]th activity, so they don't all share one photo.
    final activities = group.activities
        .where((a) => !a.plan.isDiscussion)
        .toList();
    final sibling = activities.isEmpty
        ? null
        : activities[index % activities.length].plan;
    final hero = sibling?.heroBlock;
    final borrowed = hero != null && !hero.isVideo && !hero.isYoutube
        ? [hero]
        : const <Never>[];
    final plan = ActivityPlanModel(
      activityId: f.activityId,
      title: f.title,
      // What the top of the chat shows under the photo: the questions, in
      // order.
      description: [
        for (var i = 0; i < f.questions.length; i++)
          '${i + 1}. ${f.questions[i]}',
      ].join('\n'),
      learningObjective: group.objective.objective,
      instructions: '',
      // Dummy suggested vocab: the Mission's first activity's words.
      vocab: sibling?.vocab ?? const [],
      imageURL: f.imageUrl,
      media: f.imageUrl == null ? borrowed : const [],
      req: ActivityPlanRequest(
        topic: '',
        mode: DiscussionIds.mode,
        objective: group.objective.objective,
        media: MediaEnum.nan,
        cefrLevel: sibling?.req.cefrLevel ?? LanguageLevelTypeEnum.a1,
        languageOfInstructions: 'en',
        targetLanguage: l2,
        // No roles to fill: a discussion never dims for lack of members.
        numberOfParticipants: 1,
      ),
    );
    _plans[f.activityId] = plan;
    return plan;
  }

  /// [cards] with the course's placed discussions added — each at its own
  /// coordinates, else just beside its Mission's first placed activity.
  static Future<List<QuestActivityCard>> addPins(
    List<QuestActivityCard> cards, {
    required String questId,
    required String? courseRoomId,
  }) async {
    final fixtures = await load();
    if (fixtures.isEmpty) return cards;
    final quest = (await QuestRepo.quest(questId)).asValue?.value;
    // silent-ok: the quest read reports its own failure; the pins just go
    // without discussions.
    if (quest == null) return cards;
    final byLo = _assign(
      fixtures,
      courseRoomId: courseRoomId,
      l2: quest.targetLanguage,
      loIds: quest.learningObjectiveIds,
    );
    final added = <QuestActivityCard>[];
    for (final MapEntry(key: loId, value: inMission) in byLo.entries) {
      for (final (index, f) in inMission.indexed) {
        final placed = cards
            .where(
              (c) =>
                  !c.isDiscussion &&
                  c.coordinates != null &&
                  c.learningObjectiveRefs.contains(loId),
            )
            .toList();
        final coords =
            f.coordinates ??
            (placed.isEmpty
                ? null
                : _beside(placed[index % placed.length].coordinates, index));
        if (coords == null) continue;
        added.add(
          QuestActivityCard(
            activityId: f.activityId,
            title: f.title,
            l2: quest.targetLanguage,
            coordinates: coords,
            learningObjectiveRefs: [loId],
            roleCount: 1,
            mode: DiscussionIds.mode,
          ),
        );
      }
    }
    return [...cards, ...added];
  }

  /// A spot a short walk from [coords], so the discussion's pin doesn't sit
  /// on the activity it borrowed the place from; each further discussion
  /// beside the same activity steps a little further round.
  static List<double>? _beside(List<double>? coords, int index) {
    if (coords == null) return null;
    const steps = [(0.0025, 0.0018), (-0.0025, 0.0018), (0.0025, -0.0018)];
    final (dx, dy) = steps[index % steps.length];
    final ring = 1 + index ~/ steps.length;
    return [coords[0] + dx * ring, coords[1] + dy * ring];
  }
}
