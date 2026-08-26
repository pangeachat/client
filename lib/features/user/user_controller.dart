import 'dart:async';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/analytics/client_analytics_extension.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/features/keyboards/keyboard_prompt_local_store.dart';
import 'package:fluffychat/features/languages/language_constants.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/languages/language_service.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/features/user/analytics_profile_model.dart';
import 'package:fluffychat/features/user/public_profile_model.dart';
import 'package:fluffychat/features/user/user_constants.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_mismatch_popup.dart';
import 'package:fluffychat/routes/settings/settings_learning/tool_settings_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'user_model.dart';

class LanguageUpdate {
  final LanguageModel? prevBaseLang;
  final LanguageModel? prevTargetLang;
  final LanguageModel baseLang;
  final LanguageModel targetLang;

  LanguageUpdate({
    required this.baseLang,
    required this.targetLang,
    this.prevBaseLang,
    this.prevTargetLang,
  });
}

/// Controller that manages saving and reading of user/profile information
class UserController {
  final StreamController<LanguageUpdate> languageStream =
      StreamController.broadcast();
  final StreamController<Profile> settingsUpdateStream =
      StreamController.broadcast();

  /// Fires whenever the published public profile changes — every level, XP
  /// offset, analytics room id, country or bio write lands here.
  ///
  /// [PublicProfileModel] and the analytics entries inside it are mutated in
  /// place, so a surface that read [publicProfile] during build has no way to
  /// know it went stale. Reading through this stream in `build` is what keeps
  /// the level on a language row, the analytics bar and the participant list
  /// showing one number: without it a corrected level reached whichever surface
  /// happened to rebuild next and nothing else (#8582).
  /// Null means "no profile loaded" — logout clears it, and a surface still
  /// mounted must stop showing the previous account's levels rather than hold
  /// them until an unrelated rebuild (#8531).
  final StreamController<PublicProfileModel?> publicProfileStream =
      StreamController.broadcast();

  /// Cached version of the user profile, so it doesn't have
  /// to be read in from client's account data each time it is accessed.
  Profile? _cachedProfile;

  PublicProfileModel? _publicProfile;

  /// The account [_publicProfile] was loaded for.
  ///
  /// [UserController] outlives any one login — it hangs off the process-wide
  /// [MatrixState.pangeaController] — while [client] resolves whichever account
  /// is active NOW, and the whole profile is PUT as one blob. Without the owner
  /// recorded alongside it, a blob loaded for one account is written onto the
  /// next one, giving a user a bio, country, levels and analytics room ids they
  /// never set (#8531).
  String? _publicProfileUserId;

  /// The signed-in user's public profile, or null until it has been loaded for
  /// the account that is active now. Every writer gates on that null, so it
  /// must never be left holding another account's profile.
  PublicProfileModel? get publicProfile => _publicProfile;

  /// Records the profile together with the account it belongs to. The two are
  /// only ever set as a pair, so a write cannot be aimed at the wrong account.
  void setPublicProfile(PublicProfileModel? profile, {String? userId}) {
    _publicProfile = profile;
    _publicProfileUserId = profile == null ? null : userId;
    _notifyPublicProfileChanged();
  }

  void _notifyPublicProfileChanged() {
    if (publicProfileStream.isClosed) return;
    publicProfileStream.add(_publicProfile);
  }

  /// Whether the loaded public profile belongs to the account that is active
  /// now. False while nothing is loaded, and false if the active account
  /// changed after it was loaded — both mean "do not write".
  bool get _publicProfileIsOwn =>
      _publicProfile != null && _publicProfileUserId == client.userID;

  /// Listens for account updates and updates the cached profile
  StreamSubscription? _profileListener;

  matrix.Client get client => MatrixState.pangeaController.matrixState.client;

  void _onProfileUpdate(matrix.SyncUpdate sync) {
    final prevTargetLang = userL2;
    final prevBaseLang = userL1;

    final profileData = client.accountData[UserConstants.userProfile]?.content;
    final Profile? fromAccountData = Profile.fromAccountData(profileData);
    if (fromAccountData != null && fromAccountData != _cachedProfile) {
      _cachedProfile = fromAccountData;

      if ((prevTargetLang != userL2) || (prevBaseLang != userL1)) {
        if (userL1 == null || userL2 == null) {
          // if either language is null, then we want to send a settings update instead of a language update
          ErrorHandler.logError(
            e: "One of the user languages is null. Sending settings update instead of language update.",
            data: {
              'prevBaseLang': prevBaseLang?.langCode,
              'prevTargetLang': prevTargetLang?.langCode,
              'userL1': userL1?.langCode,
              'userL2': userL2?.langCode,
            },
          );
          settingsUpdateStream.add(fromAccountData);
          return;
        }
        languageStream.add(
          LanguageUpdate(
            baseLang: userL1!,
            targetLang: userL2!,
            prevBaseLang: prevBaseLang,
            prevTargetLang: prevTargetLang,
          ),
        );
      } else {
        settingsUpdateStream.add(fromAccountData);
      }
    }
  }

  /// The user's profile. Will be empty if the client's accountData hasn't
  /// been loaded yet (if the first sync hasn't gone through yet)
  /// or if the user hasn't yer set their date of birth.
  Profile get profile {
    /// if the profile is cached, return it
    if (_cachedProfile != null) return _cachedProfile!;

    /// if account data is empty, return an empty profile
    if (client.accountData.isEmpty) {
      return Profile.emptyProfile;
    }

    /// try to get the account data in the up-to-date format
    final Profile? fromAccountData = Profile.fromAccountData(
      client.accountData[UserConstants.userProfile]?.content,
    );

    if (fromAccountData != null) {
      _cachedProfile = fromAccountData;
      return fromAccountData;
    }

    _cachedProfile = Profile.migrateFromAccountData();
    _cachedProfile?.saveProfileData();
    return _cachedProfile ?? Profile.emptyProfile;
  }

  /// Updates the user's profile with the given [update] function and saves it.
  Future<void> updateProfile(
    Profile Function(Profile) update, {
    waitForDataInSync = false,
  }) async {
    await initialize();
    final prevHash = profile.hashCode;
    // Every path that changes the target language funnels through here, so
    // this is the single place the autocorrect reset needs to be enforced.
    final updatedProfile = Profile.resetAutocorrectIfLanguageChanged(
      profile,
      update(profile),
    );

    if (updatedProfile.hashCode == prevHash) {
      // no changes were made, so don't save
      return;
    }

    await updatedProfile.saveProfileData(waitForDataInSync: waitForDataInSync);
  }

  /// True when [language] is the learner's base language, short-code
  /// compared (so 'es' matches a base of 'es-MX') — the rule
  /// [IdenticalLanguageException] enforces inside the profile write
  /// (profile.instructions.md, "Switching to the learner's base language is
  /// refused, not attempted"). Callers that offer a switch before it's
  /// attempted — the language switcher sheet's row list — use this to know
  /// up front, rather than reacting to the throw.
  static bool isBaseLanguage(LanguageModel language, String? baseLangCode) {
    final baseLangShort = baseLangCode?.split('-').first;
    return baseLangShort != null && language.langCodeShort == baseLangShort;
  }

  /// True when [language] is already the learner's target language,
  /// short-code compared the same way [isBaseLanguage] is.
  static bool isCurrentTargetLanguage(
    LanguageModel language,
    String? targetLangCode,
  ) {
    final targetLangShort = targetLangCode?.split('-').first;
    return targetLangShort != null && language.langCodeShort == targetLangShort;
  }

  /// Whether a content language chip should tint itself and offer a switch
  /// to [language] (profile.instructions.md, "Switching from context",
  /// point 6): not when it's already the learner's target, and not when
  /// it's their base language — a switch there is refused, so there's
  /// nothing to offer.
  static bool canSwitchTo(
    LanguageModel language, {
    required String? targetLangCode,
    required String? baseLangCode,
  }) =>
      !isCurrentTargetLanguage(language, targetLangCode) &&
      !isBaseLanguage(language, baseLangCode);

  /// Switches the learner's target language — the one write every inline
  /// switch path shares (profile.instructions.md, "Switching from context"):
  /// the send-time mismatch popup, the reading-toolbar snackbar, and the
  /// language switcher sheet. Throws [IdenticalLanguageException] rather
  /// than writing when [language] is the learner's base language.
  Future<void> updateTargetLanguage(LanguageModel language) async {
    await updateProfile((profile) {
      if (isBaseLanguage(language, profile.userSettings.sourceLanguage)) {
        throw IdenticalLanguageException();
      }

      return profile.copyWith(
        userSettings: profile.userSettings.copyWith(
          targetLanguage: language.langCode,
        ),
      );
    }, waitForDataInSync: true);
  }

  /// A completer for the profile model of a user.
  Completer<void> initCompleter = Completer<void>();
  bool _initializing = false;

  /// Initializes the user's profile. Runs a function to wait for account data to load,
  /// read account data into profile, and migrate any missing info from the pangea profile.
  /// Finally, it adds a listen to update the profile data when new account data comes in.
  Future<void> initialize() async {
    if (_initializing || initCompleter.isCompleted) {
      return initCompleter.future;
    }

    _initializing = true;

    try {
      await _initialize();

      _profileListener ??= client.onSync.stream
          .where((sync) => sync.accountData != null)
          .listen(_onProfileUpdate);

      _addAnalyticsRoomIdsToPublicProfile();

      if (profile.userSettings.targetLanguage != null &&
          profile.userSettings.targetLanguage!.isNotEmpty &&
          userL2 == null) {
        // update the language list and send an update to refresh analytics summary
        await PLanguageStore.initialize(forceRefresh: true);
      }
    } catch (err, s) {
      ErrorHandler.logError(e: err, s: s, data: {});
    } finally {
      if (!initCompleter.isCompleted) {
        initCompleter.complete();
      }
      _initializing = false;
    }

    return initCompleter.future;
  }

  /// Initializes the user's profile by waiting for account data to load, reading in account
  /// data to profile, and migrating from the pangea profile if the account data is not present.
  Future<void> _initialize() async {
    // Profile.effectiveAutocorrect reads the observed-keyboard store
    // synchronously (it is consumed from build methods), so the store has to
    // be in memory before any real profile exists — otherwise autocorrect
    // resolves off on iOS for whatever window the load takes.
    await ObservedKeyboardStore.ready;

    // wait for account data to load
    // as long as it's not null, then this we've already migrated the profile
    if (client.prevBatch == null) {
      await client.onSync.stream.first;
    }

    // Pinned before the awaits below: the account can change while the profile
    // request is in flight, and what is loaded here must be attributed to the
    // account it was actually read for, never to whoever is active when it
    // lands.
    final userId = client.userID;
    if (userId == null) return;
    final accountData = client.accountData[UserConstants.userProfile]?.content;
    final fromAccountData =
        Profile.fromAccountData(accountData) ?? Profile.emptyProfile;
    _cachedProfile ??= fromAccountData;

    try {
      final resp = await client.getUserProfile(userId);
      setPublicProfile(
        PublicProfileModel.fromJson(resp.additionalProperties),
        userId: userId,
      );
    } catch (e) {
      // getting a 404 error for some users without pre-existing profile
      // still want to set other properties, so catch this error
      setPublicProfile(
        PublicProfileModel(analytics: AnalyticsProfileModel()),
        userId: userId,
      );
    }

    await updatePublicProfile();

    // Do not await. This function pulls level from analytics,
    // so it waits for analytics to finish initializing. Analytics waits for user controller to
    // finish initializing, so this would cause a deadlock.
    final l2 = userL2;
    if (publicProfile!.analytics.isEmpty && l2 != null) {
      final analyticsService =
          MatrixState.pangeaController.matrixState.analyticsDataService;

      final data = await analyticsService.derivedData(l2.langCodeShort);
      updateAnalyticsProfile(languageCode: l2.langCodeShort, level: data.level);
    }
  }

  void clear() {
    _initializing = false;
    initCompleter = Completer<void>();
    _cachedProfile = null;
    setPublicProfile(null);
    _profileListener?.cancel();
    _profileListener = null;
  }

  /// Reinitializes the user's profile
  /// This method should be called whenever the user's login status changes
  Future<void> reinitialize() async {
    clear();
    await initialize();
  }

  /// Retrieves matrix access token.
  String get accessToken {
    final token = client.accessToken;
    if (token == null) {
      throw ("Trying to get accessToken with null token. User is not logged in.");
    }
    return token;
  }

  /// Checks if user data is available and the user's l2 is set.
  Future<bool> get isUserL2Set async {
    try {
      // the function fetchUserModel() uses a completer, so it shouldn't
      // re-call the endpoint if it has already been called
      await initialize();
      return profile.userSettings.targetLanguage != null;
    } catch (err, s) {
      ErrorHandler.logError(e: err, s: s, data: {});
      return false;
    }
  }

  /// Returns a boolean value indicating whether the user is currently in the trial window.
  bool inTrialWindow({int trialDays = 7}) {
    final DateTime? createdAt = profile.userSettings.createdAt;
    if (createdAt == null) {
      return false;
    }

    return createdAt.isAfter(
      DateTime.now().subtract(Duration(days: trialDays)),
    );
  }

  /// Retrieves the user's email address.
  ///
  /// This method fetches the user's email address by making a request to the
  /// Matrix server. It uses the `_pangeaController` instance to access the
  /// Matrix client and retrieve the account's third-party identifiers. It then
  /// filters the identifiers to find the first one with the medium set to
  /// `ThirdPartyIdentifierMedium.email`. Finally, it returns the email address
  /// associated with the identifier, or `null` if no email address is found.
  ///
  /// Returns:
  ///   - The user's email address as a [String], or `null` if no email address
  ///     is found.
  Future<String?> get userEmail async {
    final List<matrix.ThirdPartyIdentifier>? identifiers = await client
        .getAccount3PIDs();
    final matrix.ThirdPartyIdentifier? email = identifiers?.firstWhereOrNull(
      (identifier) =>
          identifier.medium == matrix.ThirdPartyIdentifierMedium.email,
    );
    return email?.address;
  }

  Future<void> _savePublicProfileUpdate(
    String type,
    Map<String, dynamic> content,
  ) async {
    // Last line of defence, past every caller's own guard: the profile in hand
    // is written only to the account it was loaded for. Reported once a session
    // because a refusal repeats for as long as the mismatch lasts.
    if (!_publicProfileIsOwn) {
      await ErrorHandler.logErrorOnce(
        key: 'public-profile-write-refused',
        e: "Refused to write a public profile that belongs to another account",
        s: StackTrace.current,
        data: {
          'loadedFor': _publicProfileUserId,
          'activeUser': client.userID,
          'type': type,
        },
        level: SentryLevel.warning,
      );
      return;
    }

    // Announced BEFORE the request, not after it succeeds: callers mutate the
    // in-memory profile and then call this, and that mutated object is what
    // every surface renders. Announcing only on success left a failed write
    // showing the old level while memory held the new one — a narrower version
    // of the staleness this stream exists to remove.
    _notifyPublicProfileChanged();

    try {
      await client.setUserProfile(client.userID!, type, content);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'type': type, 'content': content},
      );
    }
  }

  /// Publishes [level] as the learner's level in [languageCode]'s language.
  ///
  /// [languageCode] is required, and callers pass the language the level was
  /// actually computed from. It used to default to whatever `userL2` held when
  /// the call ran, which is not the same thing: a level is computed from one
  /// language's analytics across several awaits, and a switch landing in that
  /// window filed the old language's level under the new language's key —
  /// French's level 4 published as the learner's Dutch level (#8582).
  Future<void> updateAnalyticsProfile({
    required String languageCode,
    required int level,
  }) async {
    if (!_publicProfileIsOwn) return;

    final analytics = publicProfile!.analytics;
    final language = _shortCode(languageCode);
    final analyticsRoomId = _ownAnalyticsRoomIdFor(language);

    // target/base mirror the learner's current setting, which is independent
    // of the language this level belongs to.
    final targetLanguage = userL2?.langCodeShort;
    final baseLanguage = userL1?.langCodeShort;

    if (analytics.targetLanguage == targetLanguage &&
        analytics.baseLanguage == baseLanguage &&
        analytics.languageAnalytics?[language]?.level == level &&
        analytics.analyticsRoomIdByLanguage(language) == analyticsRoomId) {
      return;
    }

    if (targetLanguage != null) analytics.targetLanguage = targetLanguage;
    if (baseLanguage != null) analytics.baseLanguage = baseLanguage;
    analytics.setLanguageInfo(language, level, analyticsRoomId);

    await _savePublicProfileUpdate(
      PangeaEventTypes.profileAnalytics,
      publicProfile!.toJson(),
    );
  }

  static String _shortCode(String langCode) => langCode.split('-').first;

  /// The id of this user's own analytics room for [language] (a short code).
  ///
  /// Goes through [ownAnalyticsRoomLocal] rather than scanning
  /// [allMyAnalyticsRooms] directly, because a learner can end up with more
  /// than one analytics room for a language and that lookup resolves the
  /// CANONICAL one (the oldest). Analytics itself reads and writes the
  /// canonical room, and instructor analytics access is granted through
  /// whatever id is published here — so picking a different room publishes an
  /// id the rest of the system ignores, and one that can change between calls
  /// as room ordering shifts.
  String? _ownAnalyticsRoomIdFor(String language) {
    final model = PLanguageStore.byLangCode(language);
    if (model == null) return null;
    return client.ownAnalyticsRoomLocal(lang: model)?.id;
  }

  Future<void> _addAnalyticsRoomIdsToPublicProfile() async {
    if (!_publicProfileIsOwn ||
        publicProfile?.analytics.languageAnalytics == null) {
      return;
    }
    final analyticsRooms = client.allMyAnalyticsRooms;

    if (analyticsRooms.isEmpty) return;

    // Drop any analytics room id naming a room this user did not create. Such
    // an id arrived with another account's blob (#8531) and is not decoration:
    // the instructor-access grant reads it to choose the room it invites
    // instructors into, and Synapse rejects a room the caller did not create —
    // so a foreign id silently leaves this student's instructors with no
    // analytics access at all. The room id is the only field here whose owner
    // is verifiable, so it is the only one repaired; a level that came from the
    // same blob is left to the normal analytics update, which overwrites it for
    // the language the user actually studies.
    //
    // Safe against a room that has not surfaced in sync yet: the early return
    // above means this runs only once some analytics room is visible, and an id
    // cleared in error is restored by the loop below on the next init.
    publicProfile!.analytics.clearForeignAnalyticsRoomIds(
      analyticsRooms.map((room) => room.id).toSet(),
    );

    for (final analyticsRoom in analyticsRooms) {
      final madeForLang = analyticsRoom.madeForLang;
      if (madeForLang == null) continue;

      final language = _shortCode(madeForLang);
      final entry = publicProfile!.analytics.languageAnalytics?[language];
      if (entry == null || entry.analyticsRoomId == analyticsRoom.id) continue;

      publicProfile!.analytics.setLanguageInfo(
        language,
        entry.level,
        analyticsRoom.id,
      );
    }

    await _savePublicProfileUpdate(
      PangeaEventTypes.profileAnalytics,
      publicProfile!.toJson(),
    );
  }

  /// Adds [offset] to the XP offset published for [languageCode]'s language.
  /// The language is required for the same reason it is on
  /// [updateAnalyticsProfile]: the offset is derived from one language's XP.
  Future<void> addXPOffset(int offset, String languageCode) async {
    if (!_publicProfileIsOwn) return;

    final language = _shortCode(languageCode);
    publicProfile!.analytics.addXPOffset(
      language,
      offset,
      _ownAnalyticsRoomIdFor(language),
    );
    await _savePublicProfileUpdate(
      PangeaEventTypes.profileAnalytics,
      publicProfile!.toJson(),
    );
  }

  Future<void> updatePublicProfile() async {
    final current = publicProfile;
    if (current == null || !_publicProfileIsOwn) return;
    if (current.country == profile.userSettings.country &&
        current.about == profile.userSettings.about) {
      return;
    }

    // Built rather than copied: the mirror has to be able to CLEAR. country and
    // about are whatever UserSettings holds, null included — toJson omits a
    // null field and the PUT replaces the whole profile object, so the key is
    // removed server-side. A sync that can only overwrite and never clear
    // cannot converge: it re-writes the stale value on every settings update,
    // which is why a foreign bio survived every later edit (#8531).
    setPublicProfile(
      PublicProfileModel(
        analytics: current.analytics,
        country: profile.userSettings.country,
        about: profile.userSettings.about,
      ),
      userId: _publicProfileUserId,
    );

    await _savePublicProfileUpdate(
      PangeaEventTypes.profileAnalytics,
      publicProfile!.toJson(),
    );
  }

  Future<AnalyticsProfileModel> getPublicAnalyticsProfile(String userId) async {
    try {
      if (userId == BotName.byEnvironment) {
        return AnalyticsProfileModel();
      }

      final resp = await client.getUserProfile(userId);
      return AnalyticsProfileModel.fromJson(resp.additionalProperties);
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {userId: userId});
      return AnalyticsProfileModel();
    }
  }

  Future<PublicProfileModel?> getPublicProfile(String userId) async {
    try {
      if (userId == BotName.byEnvironment) {
        return PublicProfileModel(analytics: AnalyticsProfileModel());
      }

      final resp = await client.getUserProfile(userId);
      return PublicProfileModel.fromJson(resp.additionalProperties);
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {userId: userId});
      return null;
    }
  }

  bool isToolEnabled(ToolSetting setting) {
    return userToolSetting(setting);
  }

  bool userToolSetting(ToolSetting setting) {
    switch (setting) {
      case ToolSetting.interactiveTranslator:
        return profile.toolSettings.interactiveTranslator;
      case ToolSetting.interactiveGrammar:
        return profile.toolSettings.interactiveGrammar;
      case ToolSetting.immersionMode:
        return profile.toolSettings.immersionMode;
      case ToolSetting.definitions:
        return profile.toolSettings.definitions;
      case ToolSetting.autoIGC:
        return profile.toolSettings.autoIGC;
      case ToolSetting.enableAutocorrect:
        return profile.effectiveAutocorrect;
      case ToolSetting.audioWords:
        return profile.toolSettings.audioWords;
      case ToolSetting.audioChoices:
        return profile.toolSettings.audioChoices;
      case ToolSetting.audioOnNewMessage:
        return profile.toolSettings.audioOnNewMessage;
      case ToolSetting.audioOnMessageClick:
        return profile.toolSettings.audioOnMessageClick;
    }
  }

  String? get userL1Code {
    final source = profile.userSettings.sourceLanguage;
    return source == null || source.isEmpty
        ? LanguageService.systemLanguage?.langCode
        : source;
  }

  String? get userL2Code {
    final target = profile.userSettings.targetLanguage;
    return target == null || target.isEmpty ? null : target;
  }

  LanguageModel? get userL1 {
    if (userL1Code == null) return null;
    final langModel = PLanguageStore.byLangCode(userL1Code!);
    return langModel?.langCode == LanguageKeys.unknownLanguage
        ? null
        : langModel;
  }

  LanguageModel? get userL2 {
    if (userL2Code == null) return null;
    final langModel = PLanguageStore.byLangCode(userL2Code!);
    return langModel?.langCode == LanguageKeys.unknownLanguage
        ? null
        : langModel;
  }

  LanguageLevelTypeEnum? get userCefrLevel => profile.userSettings.cefrLevel;

  DateTime? get createdAt => profile.userSettings.createdAt;

  String? get voice => profile.userSettings.voice;

  bool get showDeveloperOptions => profile.toolSettings.showDeveloperOptions;

  bool get languagesSet =>
      userL1Code != null &&
      userL2Code != null &&
      userL1Code!.isNotEmpty &&
      userL2Code!.isNotEmpty &&
      userL1Code != LanguageKeys.unknownLanguage &&
      userL2Code != LanguageKeys.unknownLanguage;
}
