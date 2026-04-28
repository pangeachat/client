// ignore_for_file: implementation_imports

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:async/async.dart';
import 'package:collection/collection.dart';
import 'package:http/http.dart' hide Client;
import 'package:matrix/matrix.dart' hide Result;
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/utils/firebase_analytics.dart';
import 'package:fluffychat/pangea/join_codes/knock_with_code_extension.dart';
import 'package:fluffychat/pangea/join_codes/space_code_repo.dart';
import 'package:fluffychat/pangea/join_codes/too_many_requests_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

class NotFoundException implements Exception {}

class SpaceCodeController {
  static Completer<Result<String>>? _joinCompleter;

  static StreamController spaceCodeStream = StreamController.broadcast();

  static Future<void> cacheRoomCodeToJoin(String code) async {
    await SpaceCodeRepo.setSpaceCode(code);
    spaceCodeStream.add(code);
  }

  static Future<Result<String>> joinCachedSpaceCode({
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

  static Future<Result<String>> joinSpaceWithCode(
    String spaceCode, {
    required BuildContext context,
    required Client client,
    String? notFoundError,
    bool showLoading = true,
  }) async {
    try {
      if (_joinCompleter != null) return _joinCompleter!.future;
      _joinCompleter = Completer<Result<String>>();
      await SpaceCodeRepo.setRecentCode(spaceCode);

      // TODO this should throw error if failed
      final roomId = showLoading
          ? await _joinSpaceWithCodeWithLoading(
              spaceCode,
              context: context,
              client: client,
              notFoundError: notFoundError,
            )
          : await _joinSpaceWithCodeWithoutLoading(
              spaceCode,
              context: context,
              client: client,
            );

      GoogleAnalytics.joinClass(spaceCode);
      final result = Result.value(roomId);
      _joinCompleter?.complete(result);
      return result;
    } catch (e, s) {
      _joinCompleter?.complete(Result.error(e, s));
      ErrorHandler.logError(e: e, s: s, data: {"spaceCode": spaceCode});
      if (e is StreamedResponse && e.statusCode == 429) {
        await showDialog(
          context: context,
          builder: (context) => const TooManyRequestsDialog(),
        );
      }
      return Result.error(e, s);
    } finally {
      _joinCompleter = null;
    }
  }

  static Future<String> _joinSpaceWithCodeWithLoading(
    String spaceCode, {
    required BuildContext context,
    required Client client,
    String? notFoundError,
  }) async {
    final resp = await showFutureLoadingDialog(
      context: context,
      future: () => _joinSpaceWithCodeWithoutLoading(
        spaceCode,
        context: context,
        client: client,
      ),
      onError: (e, s) => notFoundError ?? L10n.of(context).unableToFindRoom,
      showError: (err) => err is! StreamedResponse || err.statusCode != 429,
    );

    if (resp.isError) throw resp.error!;
    return resp.result!;
  }

  static Future<String> _joinSpaceWithCodeWithoutLoading(
    String spaceCode, {
    required BuildContext context,
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
  static Future<String> _joinSpace(
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
          return roomId;
        } else if (room != null) {
          roomIdToJoin = roomId;
        }
      }

      roomIdToJoin ??= resp.roomIds.firstOrNull;
      if (roomIdToJoin == null) {
        throw NotFoundException();
      }

      await client.joinRoomById(roomIdToJoin);
      Room? room = client.getRoomById(roomIdToJoin);

      if (room == null) {
        await client.waitForRoomInSync(roomIdToJoin, join: true);
        room = client.getRoomById(roomIdToJoin);
        if (room == null) {
          throw Exception("Failed to join space with id $roomIdToJoin");
        }
      }

      if (room.membership != Membership.join) {
        await room.client.waitForRoomInSync(room.id, join: true);
      }

      // Sometimes, the invite event comes through after the join event and
      // replaces it, so membership gets out of sync. In this case,
      // load the true value from the server.
      // Related github issue: https://github.com/pangeachat/client/issues/2098
      if (room.membership !=
          room
              .getParticipants()
              .firstWhereOrNull((u) => u.id == room?.client.userID)
              ?.membership) {
        await room.requestParticipants();
      }

      return roomIdToJoin;
    } catch (e) {
      Sentry.addBreadcrumb(
        Breadcrumb(data: {"knockSpaceResponse": resp.toJson()}),
      );
      rethrow;
    }
  }
}
