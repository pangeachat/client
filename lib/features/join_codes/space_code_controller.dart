// ignore_for_file: implementation_imports

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:async/async.dart';
import 'package:collection/collection.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' hide Client;
import 'package:matrix/matrix.dart' hide Result;
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/analytics_access/join_room_analytics_access_extension.dart';
import 'package:fluffychat/features/analytics_access/join_room_analytics_consent_handler.dart';
import 'package:fluffychat/features/join_codes/knock_with_code_extension.dart';
import 'package:fluffychat/features/join_codes/space_code_repo.dart';
import 'package:fluffychat/features/join_codes/too_many_requests_dialog.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/utils/firebase_analytics.dart';
import 'package:fluffychat/utils/navigation_util.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

class NotFoundException implements Exception {}

class SpaceCodeController {
  /// In-flight joins keyed by code, so a double-tap on the same code awaits
  /// the one join — while a DIFFERENT code (a second class link arriving
  /// mid-join) runs its own, instead of being handed the first code's result
  /// (#7579).
  static final Map<String, Future<Result<JoinResponse>>> _inFlightJoins = {};

  static StreamController spaceCodeStream = StreamController.broadcast();

  /// The one post-join hop, shared by every code entry point (the coded-link
  /// page, the public course preview, the legacy cached-code path): run the
  /// analytics-consent step where the room is available locally, then open
  /// the course. When sync hasn't surfaced the room yet the join is STILL
  /// done (the join API call succeeded), so navigate to the course anyway —
  /// its panel renders a loading state until sync catches up — instead of
  /// silently stranding the user on the join page as a secret member of the
  /// course (#7579). Class codes only attach to course spaces, so the course
  /// route is the right target for the not-yet-local case; the consent
  /// notice, skipped here, resurfaces through the course-settings listener.
  static Future<void> navigateAfterJoin(
    BuildContext context,
    Client client,
    JoinResponse joinResp,
  ) async {
    final target = await resolveJoinedTarget(context, client, joinResp);
    if (target == null || !context.mounted) return;
    goToJoinedTarget(context, target);
  }

  /// The async half of the post-join hop: run the analytics-consent step where
  /// the room is available locally, and resolve where to land. Null means the
  /// learner declined consent — don't navigate. When sync hasn't surfaced the
  /// room yet the join is STILL done (the join API call succeeded), so resolve
  /// to the course anyway — its panel renders a loading state until sync
  /// catches up — instead of silently stranding the user on the join page as a
  /// secret member of the course (#7579). Class codes only attach to course
  /// spaces, so the course route is the right default for the not-yet-local
  /// case; the consent notice, skipped there, resurfaces through the
  /// course-settings listener.
  static Future<({String roomId, bool isSpace})?> resolveJoinedTarget(
    BuildContext context,
    Client client,
    JoinResponse joinResp,
  ) async {
    final room = client.getRoomById(joinResp.roomId);
    if (room == null) return (roomId: joinResp.roomId, isSpace: true);

    final handler = JoinRoomAnalyticsConsentHandler(joinResp, room);
    final joinedRoomId = await handler.handle(context);
    if (joinedRoomId == null) return null;
    return (roomId: joinedRoomId, isSpace: room.isSpace);
  }

  /// The synchronous half of the post-join hop, split from
  /// [resolveJoinedTarget] so a caller that must rewrite its own URL first
  /// (the inbound-coded join page consuming its trigger, #7579) can do both
  /// in one tick — before the rebuild the rewrite schedules can dispose it.
  static void goToJoinedTarget(
    BuildContext context,
    ({String roomId, bool isSpace}) target,
  ) {
    target.isSpace
        ? context.go(
            WorkspaceNav.openCourse(
              GoRouterState.of(context).uri,
              target.roomId,
            ),
          )
        : NavigationUtil.goToSpaceRoute(target.roomId, const [], context);
  }

  static Future<void> cacheRoomCodeToJoin(String code) async {
    await SpaceCodeRepo.setSpaceCode(code);
    spaceCodeStream.add(code);
  }

  static Future<Result<JoinResponse>> joinCachedSpaceCode({
    required BuildContext context,
    required Client client,
    String? notFoundError,
    bool showLoading = true,
  }) async {
    final String? spaceCode = SpaceCodeRepo.spaceCode;
    if (spaceCode == null) {
      return Result.error(Exception('No space code found'), null);
    }
    await SpaceCodeRepo.clearSpaceCode();
    return joinSpaceWithCode(
      spaceCode,
      context: context,
      client: client,
      notFoundError: notFoundError,
      showLoading: showLoading,
    );
  }

  static Future<Result<JoinResponse>> joinSpaceWithCode(
    String spaceCode, {
    required Client client,
    String? notFoundError,
    BuildContext? context,
    bool showLoading = true,
  }) async {
    final inFlight = _inFlightJoins[spaceCode];
    if (inFlight != null) return inFlight;
    final completer = Completer<Result<JoinResponse>>();
    _inFlightJoins[spaceCode] = completer.future;
    try {
      await SpaceCodeRepo.setRecentCode(spaceCode);

      // TODO this should throw error if failed
      final roomId = showLoading && context != null
          ? await _joinSpaceWithCodeWithLoading(
              spaceCode,
              context: context,
              client: client,
              notFoundError: notFoundError,
            )
          : await _joinSpaceWithCodeWithoutLoading(spaceCode, client: client);

      GoogleAnalytics.joinClass(spaceCode);
      final result = Result.value(roomId);
      completer.complete(result);
      return result;
    } catch (e, s) {
      completer.complete(Result.error(e, s));
      ErrorHandler.logError(e: e, s: s, data: {"spaceCode": spaceCode});
      if (e is StreamedResponse && e.statusCode == 429 && context != null) {
        await showDialog(
          context: context,
          builder: (context) => const TooManyRequestsDialog(),
        );
      }
      return Result.error(e, s);
    } finally {
      _inFlightJoins.remove(spaceCode);
    }
  }

  static Future<JoinResponse> _joinSpaceWithCodeWithLoading(
    String spaceCode, {
    required BuildContext context,
    required Client client,
    String? notFoundError,
  }) async {
    final resp = await showFutureLoadingDialog(
      context: context,
      future: () => _joinSpaceWithCodeWithoutLoading(spaceCode, client: client),
      onError: (e, s) => notFoundError ?? L10n.of(context).unableToFindRoom,
      showError: (err) => err is! StreamedResponse || err.statusCode != 429,
    );

    if (resp.isError) throw resp.error!;
    return resp.result!;
  }

  static Future<JoinResponse> _joinSpaceWithCodeWithoutLoading(
    String spaceCode, {
    required Client client,
  }) async {
    final knockResp = await _knockSpace(spaceCode, client);
    return _joinSpace(knockResp, client);
  }

  /// Step 1. Knock the space code to get potential rooms to join. If no rooms are found, throw a [NotFoundException].
  static Future<KnockSpaceResponse> _knockSpace(
    String code,
    Client client,
  ) async {
    final KnockSpaceResponse knockResult = await client.knockWithCode(code);
    if (knockResult.roomIds.isEmpty && knockResult.alreadyJoined.isEmpty) {
      throw NotFoundException();
    }
    return knockResult;
  }

  /// Step 2. Join the space. If the user has already joined a room with the code, return that room early.
  /// If they are in a room without the membership 'join', try to join that room. If no already joined rooms
  /// are found, join the first room in the list of rooms to join.
  static Future<JoinResponse> _joinSpace(
    KnockSpaceResponse resp,
    Client client,
  ) async {
    try {
      String? roomIdToJoin;
      final alreadyJoined = resp.alreadyJoined;

      // If the user has already joined a room with the code, return that room early. If they are in
      // a room without the membership 'join', try to join that room. If no already joined rooms are found,
      // join the first room in the list of rooms to join.
      for (final roomId in alreadyJoined) {
        final room = client.getRoomById(roomId);
        if (room?.membership == Membership.join) {
          return JoinResponse(
            roomId: roomId,
            shouldShowNotice: room!.shouldShowAnalyticsAccessNotice,
          );
        } else if (room != null) {
          roomIdToJoin = roomId;
        }
      }

      // A room the server says we're already in can be absent from the LOCAL
      // list on a cold boot (initial sync still running); joining it again is
      // idempotent server-side, so fall through to a join rather than a
      // not-found (#7579 — re-clicking a link for a class you're in).
      roomIdToJoin ??= resp.roomIds.firstOrNull ?? alreadyJoined.firstOrNull;
      if (roomIdToJoin == null) {
        throw NotFoundException();
      }

      final joinResp = await client.joinRoomByIdWithAccessCheck(roomIdToJoin);
      final room = client.getRoomById(roomIdToJoin);

      // The join API call above succeeded — the membership is real. A null or
      // stale local room only means sync hasn't caught up (a class-link click
      // is a fresh page load, so the client may still be mid-initial-sync);
      // don't fail a join that happened, and never wait unboundedly (#7579).
      if (room == null) return joinResp;

      // Sometimes, the invite event comes through after the join event and
      // replaces it, so membership gets out of sync. In this case,
      // load the true value from the server.
      // Related github issue: https://github.com/pangeachat/client/issues/2098
      if (room.membership !=
          room
              .getParticipants()
              .firstWhereOrNull((u) => u.id == room.client.userID)
              ?.membership) {
        await room.requestParticipants();
      }

      return joinResp;
    } catch (e) {
      Sentry.addBreadcrumb(
        Breadcrumb(data: {"knockSpaceResponse": resp.toJson()}),
      );
      rethrow;
    }
  }
}
