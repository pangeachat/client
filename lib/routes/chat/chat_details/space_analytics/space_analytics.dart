import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:get_storage/get_storage.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics/client_analytics_extension.dart';
import 'package:fluffychat/features/analytics/saved_analytics_extension.dart';
import 'package:fluffychat/features/analytics_data/analytics_settings_extension.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_builder.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/join_codes/knocked_rooms_extension.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/features/user/analytics_profile_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/chat_details/space_analytics/analytics_download_model.dart';
import 'package:fluffychat/routes/chat/chat_details/space_analytics/analytics_requests_repo.dart';
import 'package:fluffychat/routes/chat/chat_details/space_analytics/space_analytics_download_enum.dart';
import 'package:fluffychat/routes/chat/chat_details/space_analytics/space_analytics_inactive_dialog.dart';
import 'package:fluffychat/routes/chat/chat_details/space_analytics/space_analytics_request_dialog.dart';
import 'package:fluffychat/routes/chat/chat_details/space_analytics/space_analytics_summary_model.dart';
import 'package:fluffychat/routes/chat/chat_details/space_analytics/space_analytics_view.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class SpaceAnalytics extends StatefulWidget {
  final String roomId;
  const SpaceAnalytics({super.key, required this.roomId});

  @override
  SpaceAnalyticsState createState() => SpaceAnalyticsState();
}

class SpaceAnalyticsState extends State<SpaceAnalytics>
    with CoursePlanProvider {
  bool initialized = false;
  LanguageModel? _selectedLanguage;
  Map<User, AnalyticsDownload> downloads = {};

  DateTime? _lastUpdated;
  final Map<User, AnalyticsProfileModel> _profiles = {};
  final Map<LanguageModel, List<User>> _langsToUsers = {};

  Room? get room => Matrix.of(context).client.getRoomById(widget.roomId);

  LanguageModel? get filterLanguage {
    final courseLang = course?.targetLanguageModel;
    if (courseLang != null) return courseLang;
    return _selectedLanguage;
  }

  bool get canSelectLanguage =>
      !loadingCourse && course?.targetLanguageModel == null;

  LanguageModel? get _userL2 {
    final l2 = MatrixState.pangeaController.userController.userL2;
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

  List<User> _availableUsersForLang(LanguageModel lang) =>
      _langsToUsers[lang] ?? [];

  List<Room> availableAnalyticsRooms(LanguageModel lang) =>
      _availableUsersForLang(lang)
          .map((user) => _analyticsRoomOfUser(user, lang))
          .whereType<Room>()
          .toList();

  List<LanguageModel> get availableLanguages =>
      _langsToUsers.keys.toList()..sort(
        (a, b) => a
            .getDisplayName(L10n.of(context))
            .compareTo(b.getDisplayName(L10n.of(context))),
      );

  int get completedDownloads =>
      downloads.values.where((d) => d.summary != null).length;

  List<MapEntry<User, AnalyticsDownload>> get sortedDownloads {
    final entries = downloads.entries.toList();
    entries.sort((a, b) {
      final aStatus = a.value.requestStatus;
      final bStatus = b.value.requestStatus;

      // sort available downloads first
      if (aStatus == RequestStatus.available &&
          bStatus != RequestStatus.available) {
        return -1;
      } else if (aStatus != RequestStatus.available &&
          bStatus == RequestStatus.available) {
        return 1;
      }

      // then requestable users
      if (aStatus == RequestStatus.unrequested &&
          bStatus != RequestStatus.unrequested) {
        return -1;
      } else if (aStatus != RequestStatus.unrequested &&
          bStatus == RequestStatus.unrequested) {
        return 1;
      }

      // then sort not found to the end
      if (aStatus == RequestStatus.unavailable &&
          bStatus != RequestStatus.unavailable) {
        return 1;
      } else if (aStatus != RequestStatus.unavailable &&
          bStatus == RequestStatus.unavailable) {
        return -1;
      }

      return 0;
    });
    return entries;
  }

  String? get lastUpdatedString {
    if (_lastUpdated == null) return null;
    final now = DateTime.now();
    final difference = now.difference(_lastUpdated!);

    return difference.inDays > 0
        ? DateFormat('yyyy-MM-dd').format(_lastUpdated!)
        : DateFormat('HH:mm a').format(_lastUpdated!);
  }

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void didUpdateWidget(covariant SpaceAnalytics oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId) {
      initialized = false;
      _selectedLanguage = null;
      downloads = {};
      _lastUpdated = null;
      _profiles.clear();
      _langsToUsers.clear();
      _initialize();
    }
  }

  Future<void> _initialize() async {
    final courseId = room?.coursePlan?.uuid;
    if (courseId != null) {
      await loadCourse(courseId);
    }
    if (!mounted) return;

    await room?.requestParticipants(
      [Membership.join, Membership.invite, Membership.knock],
      false,
      true,
    );
    if (!mounted) return;

    final List<Future> futures = [
      GetStorage.init('analytics_request_storage'),
      _loadProfiles(),
    ];

    await Future.wait(futures);
    if (!mounted) return;

    _selectedLanguage =
        availableLanguages.contains(_userL2) || availableLanguages.isEmpty
        ? _userL2
        : availableLanguages.firstOrNull;

    await refresh();
    if (mounted) {
      setState(() => initialized = true);
    }
  }

  Future<void> _loadProfiles() async {
    final futures = _availableUsers.map((u) async {
      final resp = await MatrixState.pangeaController.userController
          .getPublicAnalyticsProfile(u.id);
      if (!mounted) return;

      _profiles[u] = resp;
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
    final lang = filterLanguage;

    if (room == null || !room!.isSpace || lang == null) return;
    await AnalyticsRequestsRepo.clear();
    if (!mounted) return;

    setState(() {
      downloads = Map.fromEntries(
        _availableUsers.map((user) {
          final room = _analyticsRoomOfUser(user, lang);
          final hasLangData = _availableUsersForLang(lang).contains(user);

          RequestStatus? requestStatus;
          if (room != null) {
            requestStatus = RequestStatus.available;
          } else if (!hasLangData) {
            requestStatus = RequestStatus.unavailable;
          } else {
            requestStatus =
                AnalyticsRequestsRepo.get(user.id, lang) ??
                RequestStatus.unrequested;
          }

          final DownloadStatus downloadStatus =
              requestStatus == RequestStatus.available
              ? DownloadStatus.loading
              : DownloadStatus.unavailable;

          return MapEntry(
            user,
            AnalyticsDownload(
              requestStatus: requestStatus,
              downloadStatus: downloadStatus,
            ),
          );
        }),
      );
    });

    for (final user in _availableUsers) {
      final analyticsRoom = _analyticsRoomOfUser(user, lang);
      if (analyticsRoom == null) {
        continue;
      }
      await _setAnalyticsModel(analyticsRoom);
      if (!mounted) return;
    }

    if (mounted) {
      setState(() {
        _lastUpdated = DateTime.now();
      });
    }
  }

  Future<void> _setAnalyticsModel(Room analyticsRoom) async {
    final String? userID = analyticsRoom.creatorId;
    final user = room?.getParticipants().firstWhereOrNull(
      (p) => p.id == userID,
    );
    if (user == null) return;

    SpaceAnalyticsSummaryModel? summary;
    final constructEvents = await analyticsRoom.getAnalyticsEvents(
      userId: userID!,
    );
    if (!mounted) return;

    if (constructEvents == null) {
      downloads[user] = AnalyticsDownload(
        requestStatus: RequestStatus.available,
        downloadStatus: DownloadStatus.complete,
        summary: SpaceAnalyticsSummaryModel.emptyModel(userID),
      );
    } else {
      summary = SpaceAnalyticsSummaryModel.fromEvents(
        userID,
        constructEvents,
        analyticsRoom.blockedConstructs,
        analyticsRoom.archivedActivitiesCount,
      );

      downloads[user] = AnalyticsDownload(
        requestStatus: RequestStatus.available,
        downloadStatus: DownloadStatus.complete,
        summary: summary,
      );
    }

    if (mounted) setState(() {});
  }

  Future<void> _requestAnalytics(User user, LanguageModel lang) async {
    RequestStatus? status = downloads[user]?.requestStatus;
    if (status == RequestStatus.unavailable ||
        status == RequestStatus.available) {
      return;
    }

    try {
      final roomId = _analyticsRoomIdOfUser(user, lang);
      if (roomId == null) return;
      await Matrix.of(context).client.knockAndRecordRoom(
        roomId,
        via: room?.spaceChildren
            .firstWhereOrNull((child) => child.roomId == roomId)
            ?.via,
        reason: widget.roomId,
      );
      status = RequestStatus.requested;
    } catch (e) {
      status = RequestStatus.unavailable;
      if (!AnalyticsRequestsRepo.getAll().any(
        (status) => status == RequestStatus.unavailable,
      )) {
        showDialog(
          context: context,
          builder: (_) {
            return const SpaceAnalyticsInactiveDialog();
          },
        );
      }
    } finally {
      if (status != null) {
        await AnalyticsRequestsRepo.set(user.id, lang, status);

        downloads[user]?.requestStatus = status;
      }

      if (mounted) setState(() {});
    }
  }

  Future<void> requestAnalytics(User user, LanguageModel lang) async {
    final status = downloads[user]?.requestStatus;
    if (status != RequestStatus.unrequested) return;

    await showFutureLoadingDialog(
      context: context,
      future: () => _requestAnalytics(user, lang),
    );
  }

  Future<void> requestAllAnalytics(LanguageModel lang) async {
    final resp = await showDialog(
      context: context,
      builder: (_) {
        return const SpaceAnalyticsRequestDialog();
      },
    );

    if (resp != true) return;
    final users = _availableUsersForLang(lang)
        .where(
          (user) => downloads[user]?.requestStatus == RequestStatus.unrequested,
        )
        .toList();

    final futures = users.map((user) => _requestAnalytics(user, lang));
    await showFutureLoadingDialog(
      context: context,
      future: () => Future.wait(futures),
    );
  }

  String? _analyticsRoomIdOfUser(User user, LanguageModel lang) {
    final profile = _profiles[user];
    if (profile == null || profile.languageAnalytics == null) return null;

    final entry = profile.languageAnalytics![lang];
    return entry?.analyticsRoomId;
  }

  Room? _analyticsRoomOfUser(User user, LanguageModel lang) {
    return Matrix.of(
      context,
    ).client.analyticsRoomLocal(lang: lang, userID: user.id);
  }

  void setSelectedLanguage(LanguageModel? lang) {
    _selectedLanguage = lang;
    refresh();
  }

  @override
  Widget build(BuildContext context) => SpaceAnalyticsView(controller: this);
}
