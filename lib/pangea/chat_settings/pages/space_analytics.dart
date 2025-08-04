import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:get_storage/get_storage.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_downloads/space_analytics_summary_model.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_list_model.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_model.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
import 'package:fluffychat/pangea/bot/utils/bot_name.dart';
import 'package:fluffychat/pangea/chat_settings/pages/space_analytics_view.dart';
import 'package:fluffychat/pangea/chat_settings/repo/analytics_requests_repo.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/pangea/learning_settings/models/language_model.dart';
import 'package:fluffychat/pangea/learning_settings/utils/p_language_store.dart';
import 'package:fluffychat/pangea/morphs/get_grammar_copy.dart';
import 'package:fluffychat/pangea/user/models/profile_model.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

enum DownloadStatus { loading, available, unavailable }

enum RequestStatus {
  available,
  unrequested,
  requested,
  notFound;

  static RequestStatus? fromString(String value) {
    switch (value) {
      case 'available':
        return RequestStatus.available;
      case 'unrequested':
        return RequestStatus.unrequested;
      case 'requested':
        return RequestStatus.requested;
      case 'notFound':
        return RequestStatus.notFound;
      default:
        return null;
    }
  }

  IconData get icon {
    switch (this) {
      case RequestStatus.available:
        return Icons.check_circle;
      case RequestStatus.unrequested:
        return Symbols.approval_delegation;
      case RequestStatus.requested:
        return Icons.mark_email_read_outlined;
      case RequestStatus.notFound:
        return Symbols.approval_delegation;
    }
  }

  String label(BuildContext context) {
    final l10n = L10n.of(context);
    switch (this) {
      case RequestStatus.available:
        return l10n.available;
      case RequestStatus.unrequested:
        return l10n.request;
      case RequestStatus.requested:
        return l10n.pending;
      case RequestStatus.notFound:
        return l10n.inactive;
    }
  }

  Color backgroundColor(BuildContext context) {
    final theme = Theme.of(context);
    switch (this) {
      case RequestStatus.available:
      case RequestStatus.unrequested:
        return theme.colorScheme.primaryContainer.withAlpha(180);
      case RequestStatus.notFound:
      case RequestStatus.requested:
        return theme.disabledColor.withAlpha(25);
    }
  }

  bool get showButton => this != RequestStatus.available;

  bool get enabled => this == RequestStatus.unrequested;
}

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
  final Map<LanguageModel, List<User>> _langsToUsers = {};

  LanguageModel? selectedLanguage;

  Room? get room => Matrix.of(context).client.getRoomById(widget.roomId);

  LanguageModel? get _userL2 {
    final l2 = MatrixState.pangeaController.languageController.userL2;
    if (l2 == null) return null;

    // Attempt to find the language model by its short code, since analytics
    // aren't divided by full language model but by short code.
    return PLanguageStore.byLangCode(l2.langCodeShort) ?? l2;
  }

  List<User> get _availableUsers =>
      room
          ?.getParticipants()
          .where(
            (member) =>
                member.id != BotName.byEnvironment &&
                member.membership == Membership.join,
          )
          .toList() ??
      [];

  List<User> get _availableUsersForLang =>
      _langsToUsers[selectedLanguage] ?? [];

  List<Room> get availableAnalyticsRooms => _availableUsersForLang
      .map((user) => _analyticsRoomOfUser(user))
      .whereType<Room>()
      .toList();

  List<LanguageModel> get availableLanguages => _langsToUsers.keys.toList()
    ..sort((a, b) => a.langCode.compareTo(b.langCode));

  int get completedDownloads =>
      downloads.values.where((d) => d.summary != null).length;

  int get requestableUsersCount => _availableUsersForLang
      .where((user) => requestStatusOfUser(user) == RequestStatus.unrequested)
      .length;

  @override
  void initState() {
    super.initState();
    selectedLanguage = _userL2;
    _initialize();
  }

  RequestStatus? _storedRequestStatus(User user) => AnalyticsRequestsRepo.get(
        user.id,
        selectedLanguage!,
      );

  RequestStatus requestStatusOfUser(User user) {
    final stored = _storedRequestStatus(user);
    if (stored != null) return stored;

    return _analyticsRoomOfUser(user) == null
        ? RequestStatus.unrequested
        : RequestStatus.available;
  }

  String? analyticsRoomIdOfUser(User user) {
    final profile = profiles[user];
    if (profile == null || profile.languageAnalytics == null) return null;

    final entry = profile.languageAnalytics![selectedLanguage];
    return entry?.analyticsRoomId;
  }

  Room? _analyticsRoomOfUser(User user) {
    return Matrix.of(context).client.rooms.firstWhereOrNull(
          (r) =>
              r.isAnalyticsRoomOfUser(user.id) &&
              r.madeForLang == selectedLanguage?.langCodeShort,
        );
  }

  void setSelectedLanguage(LanguageModel? lang) {
    if (lang == null) {
      selectedLanguage = _userL2;
    } else {
      selectedLanguage = lang;
    }

    refresh();
  }

  Future<void> _initialize() async {
    GetStorage.init('analytics_request_storage').then((_) {
      if (mounted) setState(() {});
    });

    await room?.requestParticipants(
      [Membership.join],
      false,
      true,
    );

    await _loadProfiles();
    refresh();
  }

  Future<void> _loadProfiles() async {
    final futures = _availableUsers.map((u) async {
      final resp = await MatrixState.pangeaController.userController
          .getPublicProfile(u.id);

      profiles[u] = resp;
      if (resp.languageAnalytics == null) return;

      for (final lang in resp.languageAnalytics!.entries) {
        if (lang.value.analyticsRoomId == null) continue;
        _langsToUsers[lang.key] ??= [];
        _langsToUsers[lang.key]!.add(u);
      }
    });

    await Future.wait(futures);
  }

  Future<void> refresh() async {
    if (room == null || !room!.isSpace || selectedLanguage == null) return;

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
        room?.getParticipants().firstWhereOrNull((p) => p.id == userID);
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

  Future<void> _requestAnalytics(User user) async {
    RequestStatus status = requestStatusOfUser(user);

    try {
      final roomId = analyticsRoomIdOfUser(user);
      if (roomId == null) return;
      await Matrix.of(context).client.knockRoom(roomId);
      status = RequestStatus.requested;
    } catch (e) {
      status = RequestStatus.notFound;
    } finally {
      await AnalyticsRequestsRepo.set(
        user.id,
        selectedLanguage!,
        status,
      );

      if (mounted) setState(() {});
    }
  }

  Future<void> requestAnalytics(User user) async {
    final status = requestStatusOfUser(user);
    if (status != RequestStatus.unrequested) return;

    await showFutureLoadingDialog(
      context: context,
      future: () => _requestAnalytics(user),
    );
  }

  Future<void> requestAllAnalytics() async {
    final users = _availableUsersForLang
        .where((user) => requestStatusOfUser(user) == RequestStatus.unrequested)
        .toList();

    final futures = users.map((user) => _requestAnalytics(user));
    await showFutureLoadingDialog(
      context: context,
      future: () => Future.wait(futures),
    );
  }

  @override
  Widget build(BuildContext context) => SpaceAnalyticsView(controller: this);
}
