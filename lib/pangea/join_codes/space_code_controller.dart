// ignore_for_file: implementation_imports

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' hide Client;
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/join_codes/knock_space_extension.dart';
import 'package:fluffychat/pangea/join_codes/space_code_repo.dart';
import 'package:fluffychat/pangea/join_codes/too_many_requests_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../common/controllers/base_controller.dart';

class NotFoundException implements Exception {}

class SpaceCodeController extends BaseController {
  static Future<String?> joinCachedSpaceCode(BuildContext context) async {
    final String? spaceCode = SpaceCodeRepo.spaceCode;
    if (spaceCode == null) return null;
    final spaceId = await joinSpaceWithCode(
      context,
      spaceCode,
    );

    await SpaceCodeRepo.clearSpaceCode();
    if (spaceId != null) {
      final room =
          MatrixState.pangeaController.matrixState.client.getRoomById(spaceId);
      room?.isSpace ?? true
          ? context.go('/rooms/spaces/$spaceId/details')
          : context.go('/rooms/${room?.id}');
      return spaceId;
    }
    return null;
  }

  static Future<String?> joinSpaceWithCode(
    BuildContext context,
    String spaceCode, {
    String? notFoundError,
  }) async {
    final client = MatrixState.pangeaController.matrixState.client;
    await SpaceCodeRepo.setRecentCode(spaceCode);

    final resp = await showFutureLoadingDialog<KnockSpaceResponse>(
      context: context,
      future: () async {
        final KnockSpaceResponse knockResult =
            await client.knockWithCode(spaceCode);

        if (knockResult.roomIds.isEmpty &&
            knockResult.alreadyJoined.isEmpty &&
            !knockResult.rateLimited) {
          throw NotFoundException();
        }

        return knockResult;
      },
      onError: (e, s) {
        if (e is NotFoundException ||
            e is StreamedResponse && e.statusCode == 400) {
          return L10n.of(context).unableToFindRoom;
        }

        return e;
      },
    );

    if (resp.isError || resp.result == null) {
      return null;
    }

    if (resp.result!.rateLimited) {
      await showDialog(
        context: context,
        builder: (context) => const TooManyRequestsDialog(),
      );
      return null;
    }

    String? roomIdToJoin = resp.result!.roomIds.firstOrNull;
    final alreadyJoined = resp.result!.alreadyJoined;
    if (alreadyJoined.isNotEmpty) {
      final room = client.getRoomById(alreadyJoined.first);
      if (room?.membership == Membership.join) {
        return alreadyJoined.first;
      } else if (room != null) {
        roomIdToJoin = alreadyJoined.first;
      }
    }

    if (roomIdToJoin == null) {
      return null;
    }

    await showFutureLoadingDialog(
      context: context,
      future: () => _joinSpace(roomIdToJoin!),
    );

    if (resp.isError) {
      return null;
    }

    return roomIdToJoin;
  }

  static Future<void> _joinSpace(String spaceId) async {
    final client = MatrixState.pangeaController.matrixState.client;
    await client.joinRoomById(spaceId);
    Room? room = client.getRoomById(spaceId);

    if (room == null) {
      await client.waitForRoomInSync(
        spaceId,
        join: true,
      );
      room = client.getRoomById(spaceId);
      if (room == null) {
        throw Exception("Failed to join space with id $spaceId");
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
  }
}
