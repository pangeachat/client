import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/analytics_downloads/space_analytics_summary_model.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_list_model.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_model.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
import 'package:fluffychat/pangea/bot/utils/bot_name.dart';
import 'package:fluffychat/pangea/chat_settings/pages/space_analytics_view.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/pangea/learning_settings/constants/language_constants.dart';
import 'package:fluffychat/pangea/morphs/get_grammar_copy.dart';
import 'package:fluffychat/pangea/user/models/profile_model.dart';
import 'package:fluffychat/widgets/matrix.dart';

enum DownloadStatus { loading, available, unavailable }

enum Availability { available, unavailable, request }

class AnalyticsDownload {
  DownloadStatus status;
  SpaceAnalyticsSummaryModel? summary;

  AnalyticsDownload({
    required this.status,
    this.summary,
  });
}

class SpaceAnalytics extends StatefulWidget {
  final String roomId;
  const SpaceAnalytics({super.key, required this.roomId});

  @override
  SpaceAnalyticsState createState() => SpaceAnalyticsState();
}

class SpaceAnalyticsState extends State<SpaceAnalytics> {
  Map<User, AnalyticsDownload> downloads = {};
  Map<User, PublicProfileModel> profiles = {};

  String? selectedLanguage;

  Room? get _room => Matrix.of(context).client.getRoomById(widget.roomId);

  String? get _userL2 =>
      MatrixState.pangeaController.languageController.userL2?.langCode;

  List<User> get _availableUsers =>
      _room
          ?.getParticipants()
          .where(
            (member) =>
                member.id != BotName.byEnvironment &&
                member.membership == Membership.join,
          )
          .toList() ??
      [];

  List<User> get _availableUsersForLang {
    if (selectedLanguage == null || selectedLanguage!.isEmpty) {
      return _availableUsers;
    }

    return _availableUsers.where((user) {
      final profile = profiles[user];
      if (profile == null || profile.languageAnalytics == null) {
        return false;
      }
      return profile.languageAnalytics!.entries.any(
        (entry) =>
            entry.key.langCodeShort == selectedLanguage &&
            entry.value.analyticsRoomId != null,
      );
    }).toList();
  }

  List<String> get availableLanguages {
    final List<String> langs = [];
    for (final profile in profiles.values) {
      if (profile.languageAnalytics == null) continue;
      final userLangs = profile.languageAnalytics!.entries.where(
        (entry) => entry.value.analyticsRoomId != null,
      );
      langs.addAll(userLangs.map((e) => e.key.langCodeShort));
    }

    return langs
        .toSet()
        .where((l) => l != LanguageKeys.unknownLanguage)
        .toList()
        .sorted();
  }

  int get completedDownloads =>
      downloads.values.where((d) => d.summary != null).length;

  Availability availability(User user) {
    final analyticsRoom = _analyticsRoomOfUser(user);
    if (analyticsRoom != null) return Availability.available;
    return Availability.unavailable;
  }

  @override
  void initState() {
    super.initState();
    selectedLanguage = _userL2;
    _initialize();
  }

  void setSelectedLanguage(String? lang) {
    if (lang == null || lang.isEmpty) {
      selectedLanguage = _userL2;
    } else {
      selectedLanguage = lang;
    }

    _refresh();
  }

  String? analyticsRoomIdOfUser(User user) {
    final profile = profiles[user];
    if (profile == null || profile.languageAnalytics == null) return null;

    final entry = profile.languageAnalytics!.entries.firstWhereOrNull(
      (e) => e.key.langCodeShort == selectedLanguage,
    );
    return entry?.value.analyticsRoomId;
  }

  Room? _analyticsRoomOfUser(User user) {
    return Matrix.of(context).client.rooms.firstWhereOrNull(
          (r) =>
              r.isAnalyticsRoomOfUser(user.id) &&
              r.madeForLang == selectedLanguage,
        );
  }

  Future<void> _initialize() async {
    await _room?.requestParticipants(
      [Membership.join],
      false,
      true,
    );

    await _loadProfiles();
    _refresh();
  }

  Future<void> _loadProfiles() async {
    final futures = _availableUsers.map((u) async {
      final resp = await MatrixState.pangeaController.userController
          .getPublicProfile(u.id);
      profiles[u] = resp;
    });

    await Future.wait(futures);
  }

  Future<void> _refresh() async {
    if (_room == null || !_room!.isSpace || selectedLanguage == null) return;

    setState(() {
      downloads = Map.fromEntries(
        _availableUsersForLang.map(
          (user) {
            final room = _analyticsRoomOfUser(user);
            return MapEntry(
              user,
              AnalyticsDownload(
                status: room != null
                    ? DownloadStatus.loading
                    : DownloadStatus.unavailable,
              ),
            );
          },
        ),
      );
    });

    for (final user in _availableUsersForLang) {
      final analyticsRoom = _analyticsRoomOfUser(user);
      if (analyticsRoom == null) {
        continue;
      }
      await _getAnalyticsModel(analyticsRoom);
    }
  }

  Future<void> _getAnalyticsModel(
    Room analyticsRoom,
  ) async {
    final String? userID = analyticsRoom.creatorId;
    final user =
        _room?.getParticipants().firstWhereOrNull((p) => p.id == userID);
    if (user == null) return;

    SpaceAnalyticsSummaryModel? summary;
    final constructEvents = await analyticsRoom.getAnalyticsEvents(
      userId: userID!,
    );

    if (constructEvents == null) {
      downloads[user] = AnalyticsDownload(
        status: DownloadStatus.available,
        summary: SpaceAnalyticsSummaryModel.emptyModel(userID),
      );
    } else {
      final List<OneConstructUse> uses = [];
      for (final event in constructEvents) {
        uses.addAll(event.content.uses);
      }

      final constructs = ConstructListModel(uses: uses);
      summary = SpaceAnalyticsSummaryModel.fromConstructListModel(
        userID,
        constructs,
        0,
        _getCopy,
        context,
      );

      downloads[user] = AnalyticsDownload(
        status: DownloadStatus.available,
        summary: summary,
      );
    }

    if (mounted) setState(() {});
  }

  String _getCopy(ConstructUses use) {
    return getGrammarCopy(
          category: use.category,
          lemma: use.lemma,
          context: context,
        ) ??
        use.lemma;
  }

  @override
  Widget build(BuildContext context) => SpaceAnalyticsView(controller: this);
}
