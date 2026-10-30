import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_analytics_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_response_model.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// State keys of `pangea.activity_summary`. Each slot has one writer (org doc
/// activity-summary.instructions.md, "Room state").
abstract final class ActivitySummaryStateKeys {
  /// Once the whole activity has finished, the bot's copy of every card, for
  /// older clients. Rooms from before per-learner cards hold the bot's one
  /// summary of the room here.
  static const canonical = 'canonical';

  /// The room's vocabulary and grammar use, which older clients write when
  /// the activity finishes.
  static const analytics = 'analytics';

  /// A learner's retry or feedback for one card, which the bot serves.
  static const request = 'request';

  /// Where clients wrote the summary before the bot made it (the preview
  /// endpoint reports it as `default`).
  static const legacy = '';
  static const legacyPreview = 'default';

  static const _cardPrefix = 'card:';
  static const _analyticsPrefix = 'analytics:';

  /// One learner's card: the bot's loading marker, error, or feedback.
  static String card(String userId) => '$_cardPrefix$userId';

  /// One learner's vocabulary and grammar use, written by their own client.
  static String learnerAnalytics(String userId) => '$_analyticsPrefix$userId';

  /// The learner a [card] slot belongs to; null for any other slot.
  static String? cardOwner(String stateKey) => stateKey.startsWith(_cardPrefix)
      ? stateKey.substring(_cardPrefix.length)
      : null;

  /// The learner a [learnerAnalytics] slot belongs to; null for any other.
  static String? analyticsOwner(String stateKey) =>
      stateKey.startsWith(_analyticsPrefix)
      ? stateKey.substring(_analyticsPrefix.length)
      : null;
}

/// How long the bot keeps serving requests after it last updates a finished
/// activity's cards. It leaves the room after that, so nothing would answer.
const Duration activitySummaryServiceWindow = Duration(hours: 24);

/// [owner]'s use from the `analytics:<owner>` slot that [sender] wrote. Only
/// the learner's own client writes it, so anyone else's write counts for
/// nothing.
UserConstructAnalytics? learnerAnalyticsFromSlot({
  required String owner,
  required String? sender,
  required Map<String, dynamic> content,
}) => sender == owner
    ? ActivitySummaryAnalyticsModel.fromJson(content).constructs[owner]
    : null;

/// This client is waiting for the bot to write one learner's card, since it
/// saw them finish at [since].
class ActivitySummaryWait {
  final DateTime since;

  /// The card the learner already had, made for an earlier finish. It no
  /// longer counts, and the wait ends with the bot's next write to the slot.
  final String? supersededEventId;

  const ActivitySummaryWait({required this.since, this.supersededEventId});
}

/// What one learner's card shows.
class ActivitySummaryCardView {
  final String userId;

  /// The learner's feedback; null while loading or when it failed.
  final ParticipantSummaryModel? participant;
  final bool isLoading;

  /// Nothing to show and nothing coming: the error, with a retry when
  /// [canRequest].
  final bool hasFailed;

  /// A regeneration failed; [participant] is the card the learner already
  /// had.
  final bool updateFailed;

  /// The bot is still serving this room, so a retry or feedback is answered.
  final bool canRequest;

  /// When [isLoading] ends if nothing lands first. Nothing rebuilds on its
  /// own at that moment, so the owner schedules a recompute.
  final DateTime? loadingDeadline;

  /// The language [participant] is written in, and choreo's id for the
  /// stored row behind it. Only the bot's cards carry them.
  final String? langCode;
  final String? requestHash;

  const ActivitySummaryCardView({
    required this.userId,
    required this.participant,
    required this.isLoading,
    required this.hasFailed,
    required this.updateFailed,
    required this.canRequest,
    required this.loadingDeadline,
    this.langCode,
    this.requestHash,
  });

  /// Whether a viewer whose first language is [viewerL1] gets this card
  /// translated rather than as written.
  bool needsTranslation(String? viewerL1) =>
      participant != null &&
      langCode != null &&
      viewerL1 != null &&
      !PLanguageStore.sameWrittenLanguage(langCode!, viewerL1);

  /// This card shown in [translation], or loading while the translation is
  /// fetched.
  ActivitySummaryCardView translatedTo(ParticipantSummaryModel? translation) =>
      ActivitySummaryCardView(
        userId: userId,
        participant: translation,
        isLoading: translation == null,
        hasFailed: false,
        updateFailed: updateFailed,
        canRequest: canRequest,
        loadingDeadline: null,
      );
}

/// What an activity shows where its summary goes: one card per learner who
/// has finished, in role order.
class ActivitySummaryView {
  final List<ActivitySummaryCardView> cards;

  /// The room-wide text of a room summarized before per-learner cards, in
  /// [groupLangCode] and stored under [groupRequestHash]. Null when there is
  /// none.
  final String? groupSummary;
  final String? groupLangCode;
  final String? groupRequestHash;

  const ActivitySummaryView({
    required this.cards,
    this.groupSummary,
    this.groupLangCode,
    this.groupRequestHash,
  });

  static const empty = ActivitySummaryView(cards: []);

  ActivitySummaryCardView? cardFor(String? userId) =>
      cards.firstWhereOrNull((card) => card.userId == userId);

  bool get isLoading => cards.any((card) => card.isLoading);

  /// The first moment a card stops loading by itself.
  DateTime? get loadingDeadline =>
      cards.map((card) => card.loadingDeadline).nonNulls.minOrNull;
}

/// A summary slot, and where it came from.
class _SummarySlot {
  final ActivitySummaryModel model;

  /// Null for a slot held as stripped state, which has neither.
  final String? eventId;
  final DateTime? sentAt;

  /// The bot wrote it, so it can serve requests for it.
  final bool fromBot;

  /// It summarizes the whole room, from before per-learner cards.
  final bool roomWide;

  const _SummarySlot(
    this.model, {
    required this.eventId,
    required this.sentAt,
    required this.fromBot,
    required this.roomWide,
  });

  /// The server time (ms) the call behind this slot started. A request or
  /// finish no newer than this has been handled.
  int? get handledUntil =>
      model.callStartedTs ?? sentAt?.millisecondsSinceEpoch;
}

extension ActivitySummaryRoomExtension on Room {
  /// [stateKey]'s slot if the bot wrote it. Any learner can write this event
  /// type, so a write by anyone else is ignored.
  Event? _botSlot(String stateKey) {
    final event = getState(PangeaEventTypes.activitySummary, stateKey);
    // An invited room holds stripped state only, with no timestamps.
    if (event is! Event) return null;
    if (event.senderId != BotName.byEnvironment) {
      ErrorHandler.logErrorOnce(
        key: 'activity_summary_foreign_slot:$id:$stateKey',
        e: 'Bot-only activity summary slot written by another sender',
        data: {'roomID': id, 'stateKey': stateKey, 'sender': event.senderId},
      );
      return null;
    }
    return event;
  }

  ActivitySummaryModel? _parseSummary(StrippedStateEvent? event) {
    if (event == null) return null;
    try {
      return ActivitySummaryModel.fromJson(event.content);
    } catch (e, s) {
      ErrorHandler.logErrorOnce(
        key: 'activity_summary_parse:$id:${event.stateKey}',
        e: e,
        s: s,
        data: {'roomID': id, 'stateKey': event.stateKey},
      );
      return null;
    }
  }

  _SummarySlot? _cardSlot(String userId) {
    final event = _botSlot(ActivitySummaryStateKeys.card(userId));
    final model = _parseSummary(event);
    if (event == null || model == null) return null;
    return _SummarySlot(
      model,
      eventId: event.eventId,
      sentAt: event.originServerTs,
      fromBot: true,
      roomWide: false,
    );
  }

  /// The summary of a room from before per-learner cards: the bot's, else
  /// one an older client wrote under the viewer's L1 or the unkeyed slot.
  _SummarySlot? get _roomWideSlot {
    final canonical = _botSlot(ActivitySummaryStateKeys.canonical);
    final canonicalModel = _parseSummary(canonical);
    if (canonical != null && canonicalModel != null) {
      return _SummarySlot(
        canonicalModel,
        eventId: canonical.eventId,
        sentAt: canonical.originServerTs,
        fromBot: true,
        roomWide: true,
      );
    }

    final l1 = MatrixState.pangeaController.userController.userL1Code;
    for (final key in [?l1, ActivitySummaryStateKeys.legacy]) {
      final event = getState(PangeaEventTypes.activitySummary, key);
      final model = _parseSummary(event);
      if (model == null) continue;
      return _SummarySlot(
        model,
        eventId: event is Event ? event.eventId : null,
        sentAt: event is Event ? event.originServerTs : null,
        fromBot: false,
        roomWide: true,
      );
    }
    return null;
  }

  /// The room-wide summary of a room from before per-learner cards.
  ActivitySummaryModel? get activitySummary => _roomWideSlot?.model;

  /// [userId]'s feedback: from their own card, else from the room-wide
  /// summary.
  ParticipantSummaryModel? activitySummaryFor(String userId) =>
      (_cardSlot(userId) ?? _roomWideSlot)?.model.summary?.userSummary(userId);

  /// The learners holding a role, in role order. The bot gets no card.
  Iterable<ActivityRoleModel> get _learnerRoles =>
      (assignedRoles?.values ?? const <ActivityRoleModel>[]).where(
        (role) => role.userId != BotName.byEnvironment,
      );

  /// The learners who have finished, whose cards are due.
  Set<String> get finishedLearnerIds => {
    for (final role in _learnerRoles)
      if (role.isFinished) role.userId,
  };

  /// True once the whole activity has finished and a card is in the room.
  /// The cards carry the learners' goals from then on, so the goal header
  /// steps aside (#8289). Until then the header stays, with its end-for-all.
  bool get hasGeneratedActivitySummary {
    if (!isActivityFinished) return false;
    final roomWide = _roomWideSlot;
    return _learnerRoles.any(
      (role) =>
          (_cardSlot(role.userId) ?? roomWide)?.model.summary?.userSummary(
            role.userId,
          ) !=
          null,
    );
  }

  /// Whether [userId] has a card slot, or a room-wide summary stands in.
  bool hasActivitySummarySlot(String userId) =>
      (_cardSlot(userId) ?? _roomWideSlot) != null;

  /// The card [userId] had when this client saw them finish, if the bot made
  /// it for an earlier finish: its call started before the role write that
  /// finished them. Both are server times, so device clocks don't matter.
  String? activitySummaryCardBefore(String userId) {
    final slot = _cardSlot(userId) ?? _roomWideSlot;
    final roles = getState(PangeaEventTypes.activityRole);
    final handledUntil = slot?.handledUntil;
    if (handledUntil == null || roles is! Event) return null;
    return handledUntil < roles.originServerTs.millisecondsSinceEpoch
        ? slot!.eventId
        : null;
  }

  /// The room's own vocabulary and grammar use, from an older client's room
  /// slot or, for a session summarized before that slot existed, the old
  /// summary.
  ActivitySummaryAnalyticsModel? get _roomAnalytics {
    final event = getState(
      PangeaEventTypes.activitySummary,
      ActivitySummaryStateKeys.analytics,
    );
    if (event != null) {
      try {
        return ActivitySummaryAnalyticsModel.fromJson(event.content);
      } catch (e, s) {
        ErrorHandler.logErrorOnce(
          key: 'activity_summary_parse:$id:${event.stateKey}',
          e: e,
          s: s,
          data: {'roomID': id, 'stateKey': event.stateKey},
        );
      }
    }
    return activitySummary?.analytics;
  }

  /// Each learner's vocabulary and grammar use: from their own slot, else
  /// from the room's.
  ActivitySummaryAnalyticsModel? get activitySummaryAnalytics {
    var analytics = _roomAnalytics;
    final slots = states[PangeaEventTypes.activitySummary] ?? const {};
    for (final MapEntry(key: stateKey, value: event) in slots.entries) {
      final owner = ActivitySummaryStateKeys.analyticsOwner(stateKey);
      if (owner == null) continue;
      try {
        final own = learnerAnalyticsFromSlot(
          owner: owner,
          sender: event.senderId,
          content: event.content,
        );
        if (own == null) {
          ErrorHandler.logErrorOnce(
            key: 'activity_summary_foreign_slot:$id:$stateKey',
            e: 'Learner analytics slot written by another sender',
            data: {'roomID': id, 'stateKey': stateKey},
          );
          continue;
        }
        (analytics ??= ActivitySummaryAnalyticsModel()).constructs[owner] = own;
      } catch (e, s) {
        ErrorHandler.logErrorOnce(
          key: 'activity_summary_parse:$id:$stateKey',
          e: e,
          s: s,
          data: {'roomID': id, 'stateKey': stateKey},
        );
      }
    }
    return analytics;
  }

  /// Whether this learner's own analytics are due: they have finished, and
  /// nothing written since covers that finish. A learner who resumes and ends
  /// again is due again, since their messages changed.
  bool get needsOwnActivityAnalytics {
    final userId = client.userID;
    final finishedAt = ownRoleState?.finishedAt;
    if (userId == null || finishedAt == null) return false;

    bool coversFinish(String stateKey, {String? writer}) {
      final event = getState(PangeaEventTypes.activitySummary, stateKey);
      return event is Event &&
          (writer == null || event.senderId == writer) &&
          !event.originServerTs.isBefore(finishedAt);
    }

    // An older client's room slot written after the finish has them too.
    return !coversFinish(
          ActivitySummaryStateKeys.learnerAnalytics(userId),
          writer: userId,
        ) &&
        !coversFinish(ActivitySummaryStateKeys.analytics);
  }

  /// Computes this learner's vocabulary and grammar use from their own
  /// messages and writes it to their own slot. Only their client can compute
  /// it, and their messages are final once they end.
  Future<void> writeOwnActivityAnalytics() async {
    final userId = client.userID;
    // A signed-out account has nothing to record (CLIENT-EQW, #9099).
    if (userId == null || !client.isLogged()) return;

    final events = await getAllEvents();
    final timeline = this.timeline ?? await getTimeline();
    final messageEvents = getPangeaMessageEvents(
      events,
      timeline,
      msgtypes: [MessageTypes.Text, MessageTypes.Audio],
    );
    final analytics = ActivitySummaryAnalyticsModel();
    for (final messageEvent in messageEvents) {
      if (messageEvent.senderId == userId) {
        analytics.addMessageConstructs(messageEvent);
      }
    }
    // An entry even with no uses, so readers know it was counted.
    analytics.constructs[userId] ??= UserConstructAnalytics(userId);
    await client.setRoomStateWithKey(
      id,
      PangeaEventTypes.activitySummary,
      ActivitySummaryStateKeys.learnerAnalytics(userId),
      analytics.toJson(),
    );
  }

  /// Asks the bot to retry [userId]'s card, or to regenerate it with
  /// [feedback]. The timestamp keeps a repeat request from matching the
  /// current state, which the homeserver would drop as a no-op.
  Future<void> requestActivitySummary({
    required String userId,
    String? feedback,
  }) async {
    if (!client.isLogged()) return;
    await client.setRoomStateWithKey(
      id,
      PangeaEventTypes.activitySummary,
      ActivitySummaryStateKeys.request,
      {
        ModelKey.userId: userId,
        'feedback': ?feedback,
        'requested_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }

  bool get _botIsJoined =>
      getParticipants()
          .firstWhereOrNull((u) => u.id == BotName.byEnvironment)
          ?.membership ==
      Membership.join;

  /// When the bot last wrote a card or its canonical copy.
  DateTime? get _lastBotSummaryWrite {
    final slots = states[PangeaEventTypes.activitySummary] ?? const {};
    return [
      for (final MapEntry(key: stateKey, value: event) in slots.entries)
        if (event is Event &&
            event.senderId == BotName.byEnvironment &&
            (stateKey == ActivitySummaryStateKeys.canonical ||
                ActivitySummaryStateKeys.cardOwner(stateKey) != null))
          event.originServerTs,
    ].maxOrNull;
  }

  /// A request for [userId]'s card the bot has not started serving yet, by
  /// the rule the bot uses: newer than the start of the call behind [slot].
  /// A card serves requests that name its learner; a room-wide summary, or
  /// none yet, also serves an older client's, which names nobody.
  bool _requestPending(Event? request, _SummarySlot? slot, String userId) {
    if (request == null) return false;
    final named = request.content[ModelKey.userId];
    final forThisCard =
        (slot != null && slot.roomWide) ||
        named == userId ||
        (slot == null && named == null);
    if (!forThisCard) return false;
    final handledUntil = slot?.handledUntil;
    return handledUntil == null ||
        request.originServerTs.millisecondsSinceEpoch > handledUntil;
  }

  /// What the room shows where its summary goes. Each learner's card appears
  /// once they finish, to them at once and to the others once those have
  /// finished too.
  ///
  /// [waits] holds the learners whose finish this client saw with no card,
  /// or with one made for an earlier finish; the bot gets
  /// [ActivitySummaryModel.requestTimeout] from then to write one. Every
  /// loading state ends at a deadline, so a bot or network that never
  /// answers ends in the error, not an endless spinner (#8362).
  ActivitySummaryView activitySummaryView({
    Map<String, ActivitySummaryWait> waits = const {},
  }) {
    final finished = isActivityFinished;
    if (!finished && !hasCompletedRole) return ActivitySummaryView.empty;

    final now = DateTime.now();
    final roomWide = _roomWideSlot;
    final request = getState(
      PangeaEventTypes.activitySummary,
      ActivitySummaryStateKeys.request,
    );
    final lastBotWrite = _lastBotSummaryWrite;

    final cards = <ActivitySummaryCardView>[];
    for (final role in _learnerRoles) {
      final userId = role.userId;
      final slot = _cardSlot(userId) ?? roomWide;
      final model = slot?.model;
      final entry = model?.summary?.userSummary(userId);
      // A learner still playing has no card yet, even one from before they
      // resumed. Past the end, any card the room holds for them shows.
      if (!role.isFinished && (!finished || entry == null)) continue;
      // A room-wide summary that has no feedback for them has no card.
      if (slot != null && slot.roomWide && model?.summary != null) {
        if (entry == null) continue;
      }

      final wait = waits[userId];
      final waiting =
          wait != null &&
          (slot == null ||
              (slot.eventId != null && slot.eventId == wait.supersededEventId));
      final loadingDeadline = [
        if (model != null && model.isLoading) model.loadingDeadline,
        if (request is Event && _requestPending(request, slot, userId))
          request.originServerTs.add(ActivitySummaryModel.requestTimeout),
        if (waiting) wait.since.add(ActivitySummaryModel.requestTimeout),
      ].nonNulls.where((deadline) => deadline.isAfter(now)).maxOrNull;
      final isLoading = loadingDeadline != null;
      final shown = isLoading ? null : entry;

      // Once the bot has written the slot, the activity running or its
      // service window says whether it is still here. Before that, only its
      // membership can, and members load lazily, so it decides nothing else.
      // A summary an older client wrote gets no feedback: the bot has none
      // of its own to regenerate.
      final bool canRequest;
      if (slot == null) {
        canRequest = _botIsJoined;
      } else if (!slot.fromBot) {
        canRequest = model?.summary == null && _botIsJoined;
      } else {
        canRequest =
            model?.summary == null ||
            !finished ||
            (lastBotWrite ?? now)
                .add(activitySummaryServiceWindow)
                .isAfter(now);
      }

      cards.add(
        ActivitySummaryCardView(
          userId: userId,
          participant: shown,
          isLoading: isLoading,
          hasFailed: !isLoading && shown == null,
          // The bot's call failed, or never came for a later finish.
          updateFailed: shown != null && (model!.hasError || waiting),
          canRequest: canRequest,
          loadingDeadline: loadingDeadline,
          langCode: model?.langCode,
          requestHash: model?.requestHash,
        ),
      );
    }

    final groupText = roomWide?.model.summary?.summary;
    final usesRoomWide = cards.any(
      (card) => _cardSlot(card.userId) == null && roomWide != null,
    );
    return ActivitySummaryView(
      cards: cards,
      groupSummary: usesRoomWide && groupText != null && groupText.isNotEmpty
          ? groupText
          : null,
      groupLangCode: roomWide?.model.langCode,
      groupRequestHash: roomWide?.model.requestHash,
    );
  }
}
