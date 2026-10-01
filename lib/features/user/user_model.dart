import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/instructions/instruction_settings.dart';
import 'package:fluffychat/features/keyboards/keyboard_prompt_local_store.dart';
import 'package:fluffychat/features/user/user_constants.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/routes/settings/settings_learning/gender_enum.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/routes/settings/settings_learning/tool_settings_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../languages/language_model.dart';

/// The user's settings learning settings.
class UserSettings {
  final DateTime? dateOfBirth;
  final DateTime? createdAt;
  final bool? publicProfile;
  final String? targetLanguage;
  final String? sourceLanguage;

  /// When true, the app UI (menus, buttons, labels) is shown in the user's
  /// target language for immersion instead of their source/native language.
  /// Untranslated keys fall back to English.
  final bool appLanguageIsTarget;
  final GenderEnum gender;
  final String? country;
  final String? about;
  final LanguageLevelTypeEnum cefrLevel;
  final String? voice;

  UserSettings({
    this.dateOfBirth,
    this.createdAt,
    this.publicProfile,
    this.targetLanguage,
    this.sourceLanguage,
    this.appLanguageIsTarget = false,
    this.gender = GenderEnum.unselected,
    this.country,
    this.about,
    this.cefrLevel = LanguageLevelTypeEnum.a1,
    this.voice,
  });

  factory UserSettings.fromJson(Map<String, dynamic> json) => UserSettings(
    dateOfBirth: json[UserConstants.userDateOfBirth] != null
        ? DateTime.parse(json[UserConstants.userDateOfBirth])
        : null,
    createdAt: json[UserConstants.userCreatedAt] != null
        ? DateTime.parse(json[UserConstants.userCreatedAt])
        : null,
    publicProfile: json[UserConstants.publicProfile],
    targetLanguage: json[ModelKey.targetLanguage],
    sourceLanguage: json[ModelKey.sourceLanguage],
    appLanguageIsTarget: json[ModelKey.appLanguageIsTarget] as bool? ?? false,
    gender: json[UserConstants.userGender] is String
        ? GenderEnumExtension.fromString(json[UserConstants.userGender])
        : GenderEnum.unselected,
    country: json[UserConstants.userCountry],
    about: json[UserConstants.userAbout],
    cefrLevel: json[UserConstants.cefrLevel] is String
        ? LanguageLevelTypeEnum.fromString(json[UserConstants.cefrLevel])
        : LanguageLevelTypeEnum.a1,
    voice: json[ModelKey.voice],
  );

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data[UserConstants.userDateOfBirth] = dateOfBirth?.toIso8601String();
    data[UserConstants.userCreatedAt] = createdAt?.toIso8601String();
    data[UserConstants.publicProfile] = publicProfile;
    data[ModelKey.targetLanguage] = targetLanguage;
    data[ModelKey.sourceLanguage] = sourceLanguage;
    data[ModelKey.appLanguageIsTarget] = appLanguageIsTarget;
    data[UserConstants.userGender] = gender.string;
    data[UserConstants.userCountry] = country;
    data[UserConstants.userAbout] = about;
    data[UserConstants.cefrLevel] = cefrLevel.string;
    data[ModelKey.voice] = voice;
    return data;
  }

  /// Reads the pre-migration, per-key account-data shape.
  ///
  /// [client] names the account to read. Omitted, it is the globally active
  /// one — which is all every existing caller ever meant, since they run from
  /// a settings surface belonging to whoever is signed in. Passed explicitly,
  /// this reads a SPECIFIC account's legacy data instead: a call resolves its
  /// languages from the room's own account rather than from whichever account
  /// happens to be foregrounded (see [UserController.languageCodesFor]).
  static UserSettings? migrateFromAccountData({Client? client}) {
    final accountData =
        (client ?? MatrixState.pangeaController.matrixState.client).accountData;

    if (!accountData.containsKey(UserConstants.userDateOfBirth)) return null;
    final dobContent = accountData[UserConstants.userDateOfBirth]!
        .content[UserConstants.userDateOfBirth];

    String? dobString;
    if (dobContent != null) {
      dobString = dobContent as String;
    }

    DateTime dob;
    try {
      dob = DateTime.parse(dobString!);
    } catch (_) {
      return null;
    }

    final createdAtContent = accountData[UserConstants.userCreatedAt]
        ?.content[UserConstants.userCreatedAt];
    DateTime? createdAt;
    if (createdAtContent != null) {
      try {
        createdAt = DateTime.parse(createdAtContent as String);
      } catch (_) {
        createdAt = null;
      }
    }

    return UserSettings(
      dateOfBirth: dob,
      createdAt: createdAt,
      publicProfile:
          (accountData[UserConstants.publicProfile]?.content[UserConstants
                  .publicProfile]
              as bool?) ??
          false,
      targetLanguage:
          accountData[ModelKey.targetLanguage]?.content[ModelKey.targetLanguage]
              as String?,
      sourceLanguage:
          accountData[ModelKey.sourceLanguage]?.content[ModelKey.sourceLanguage]
              as String?,
      country:
          accountData[UserConstants.userCountry]?.content[UserConstants
                  .userCountry]
              as String?,
    );
  }

  UserSettings copyWith({
    DateTime? dateOfBirth,
    DateTime? createdAt,
    bool? publicProfile,
    String? targetLanguage,
    String? sourceLanguage,
    bool? appLanguageIsTarget,
    GenderEnum? gender,
    String? country,
    String? about,
    LanguageLevelTypeEnum? cefrLevel,
    String? voice,
    bool setVoiceNull = false,
  }) {
    return UserSettings(
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      createdAt: createdAt ?? this.createdAt,
      publicProfile: publicProfile ?? this.publicProfile,
      targetLanguage: targetLanguage ?? this.targetLanguage,
      sourceLanguage: sourceLanguage ?? this.sourceLanguage,
      appLanguageIsTarget: appLanguageIsTarget ?? this.appLanguageIsTarget,
      gender: gender ?? this.gender,
      country: country ?? this.country,
      about: about ?? this.about,
      cefrLevel: cefrLevel ?? this.cefrLevel,
      voice: setVoiceNull ? null : (voice ?? this.voice),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is UserSettings &&
        other.dateOfBirth == dateOfBirth &&
        other.createdAt == createdAt &&
        (other.publicProfile ?? false) == (publicProfile ?? false) &&
        other.targetLanguage == targetLanguage &&
        other.sourceLanguage == sourceLanguage &&
        other.appLanguageIsTarget == appLanguageIsTarget &&
        other.gender == gender &&
        other.country == country &&
        other.about == about &&
        other.cefrLevel == cefrLevel &&
        other.voice == voice;
  }

  @override
  int get hashCode => Object.hashAll([
    dateOfBirth.hashCode,
    createdAt.hashCode,
    (publicProfile ?? false).hashCode,
    targetLanguage.hashCode,
    sourceLanguage.hashCode,
    appLanguageIsTarget.hashCode,
    gender.hashCode,
    country.hashCode,
    about.hashCode,
    cefrLevel.hashCode,
    voice.hashCode,
  ]);
}

/// The user's language tool settings.
class UserToolSettings {
  // Key of the retired enableTTS toggle, kept as a read-fallback so stored
  // profiles seed the words/choices audio toggles.
  static const _legacyEnableTTSKey = 'ToolSetting.enableTTS';

  final bool interactiveTranslator;
  final bool interactiveGrammar;
  final bool immersionMode;
  final bool definitions;
  final bool autoIGC;
  final bool audioWords;
  final bool audioChoices;
  final bool audioOnNewMessage;
  final bool audioOnMessageClick;

  /// Writing assistance's Listen First mode, remembered across matches and
  /// sessions once the learner turns it on.
  ///
  /// It exists for learners who know a language by ear before its script, and
  /// that is a property of the learner, not of one correction — resetting it
  /// per match made them re-arm it on every highlighted word. Default off, so
  /// a single tap keeps selecting for everyone who has not asked otherwise.
  /// See writing-assistance.instructions.md.
  final bool listenFirst;

  /// The user's explicit autocorrect choice, or null when they have never
  /// touched the toggle. Kept unresolved in storage so each device applies its
  /// own [enableAutocorrectPlatformDefault] — resolving at write time would
  /// sync an Android "on" to the same account's iOS devices.
  final bool? enableAutocorrectChoice;
  final bool showDeveloperOptions;

  const UserToolSettings({
    this.interactiveTranslator = true,
    this.interactiveGrammar = true,
    this.immersionMode = false,
    this.definitions = true,
    this.autoIGC = true,
    this.audioWords = true,
    this.audioChoices = true,
    this.audioOnNewMessage = true,
    this.audioOnMessageClick = true,
    bool? enableAutocorrect,
    this.showDeveloperOptions = false,
    this.listenFirst = false,
  }) : enableAutocorrectChoice = enableAutocorrect;

  /// Device autocorrect defaults on only where the composer can tell the
  /// keyboard which language to correct in — Android, via `hintLocales`
  /// (#8466). iOS stays off until #8465 gives it a language-targeted keyboard.
  /// Reads [defaultTargetPlatform] rather than dart:io so tests can override it.
  static bool get enableAutocorrectPlatformDefault =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get enableAutocorrect =>
      enableAutocorrectChoice ?? enableAutocorrectPlatformDefault;

  factory UserToolSettings.fromJson(
    Map<String, dynamic> json,
  ) => UserToolSettings(
    interactiveTranslator:
        json[ToolSetting.interactiveTranslator.toString()] ?? true,
    interactiveGrammar: json[ToolSetting.interactiveGrammar.toString()] ?? true,
    immersionMode: false,
    definitions: json[ToolSetting.definitions.toString()] ?? true,
    autoIGC: json[UserConstants.autoIGC] ?? true,
    audioWords: json["audioWords"] ?? json[_legacyEnableTTSKey] ?? true,
    audioChoices: json["audioChoices"] ?? json[_legacyEnableTTSKey] ?? true,
    // Deliberately not seeded from the retired audioIncomingMessages key: it
    // was opt-in default-off, so a stored false is almost always the old
    // default rather than a choice, and #8264 turns message audio on for
    // everyone.
    audioOnNewMessage: json["audioOnNewMessage"] ?? true,
    audioOnMessageClick: json["audioOnMessageClick"] ?? true,
    // Before #8466 every saved profile carried this key (default-off was
    // written back), so a stored false is kept as the user's choice — only
    // profiles without the key pick up the platform default.
    enableAutocorrect: json["enableAutocorrect"] as bool?,
    showDeveloperOptions: json["showDeveloperOptions"] ?? false,
    listenFirst: json["listenFirst"] ?? false,
  );

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data[ToolSetting.interactiveTranslator.toString()] = interactiveTranslator;
    data[ToolSetting.interactiveGrammar.toString()] = interactiveGrammar;
    data[ToolSetting.immersionMode.toString()] = immersionMode;
    data[ToolSetting.definitions.toString()] = definitions;
    data[UserConstants.autoIGC] = autoIGC;
    data["audioWords"] = audioWords;
    data["audioChoices"] = audioChoices;
    data["audioOnNewMessage"] = audioOnNewMessage;
    data["audioOnMessageClick"] = audioOnMessageClick;
    if (enableAutocorrectChoice != null) {
      data["enableAutocorrect"] = enableAutocorrectChoice;
    }
    data["showDeveloperOptions"] = showDeveloperOptions;
    data["listenFirst"] = listenFirst;
    return data;
  }

  factory UserToolSettings.migrateFromAccountData() {
    final accountData =
        MatrixState.pangeaController.matrixState.client.accountData;
    return UserToolSettings(
      interactiveTranslator:
          (accountData[ToolSetting.interactiveTranslator.toString()]
                  ?.content[ToolSetting.interactiveTranslator.toString()]
              as bool?) ??
          true,
      interactiveGrammar:
          (accountData[ToolSetting.interactiveGrammar.toString()]
                  ?.content[ToolSetting.interactiveGrammar.toString()]
              as bool?) ??
          true,
      immersionMode: false,
      definitions:
          (accountData[ToolSetting.definitions.toString()]?.content[ToolSetting
                  .definitions
                  .toString()]
              as bool?) ??
          true,
      autoIGC:
          (accountData[ToolSetting.autoIGC.toString()]?.content[ToolSetting
                  .autoIGC
                  .toString()]
              as bool?) ??
          true,
    );
  }

  UserToolSettings copyWith({
    bool? interactiveTranslator,
    bool? interactiveGrammar,
    bool? immersionMode,
    bool? definitions,
    bool? autoIGC,
    bool? audioWords,
    bool? audioChoices,
    bool? audioOnNewMessage,
    bool? audioOnMessageClick,
    bool? enableAutocorrect,

    /// Resets the autocorrect choice to unresolved (null) rather than
    /// keeping it — used when the target language changes, since a choice
    /// made for one language says nothing about the next (see
    /// target-language-keyboard.instructions.md). Ignored if
    /// [enableAutocorrect] is also passed.
    bool setEnableAutocorrectNull = false,
    bool? showDeveloperOptions,
    bool? listenFirst,
  }) {
    return UserToolSettings(
      interactiveTranslator:
          interactiveTranslator ?? this.interactiveTranslator,
      interactiveGrammar: interactiveGrammar ?? this.interactiveGrammar,
      immersionMode: immersionMode ?? this.immersionMode,
      definitions: definitions ?? this.definitions,
      autoIGC: autoIGC ?? this.autoIGC,
      audioWords: audioWords ?? this.audioWords,
      audioChoices: audioChoices ?? this.audioChoices,
      audioOnNewMessage: audioOnNewMessage ?? this.audioOnNewMessage,
      audioOnMessageClick: audioOnMessageClick ?? this.audioOnMessageClick,
      enableAutocorrect: setEnableAutocorrectNull
          ? null
          : (enableAutocorrect ?? enableAutocorrectChoice),
      showDeveloperOptions: showDeveloperOptions ?? this.showDeveloperOptions,
      listenFirst: listenFirst ?? this.listenFirst,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is UserToolSettings &&
        other.interactiveTranslator == interactiveTranslator &&
        other.interactiveGrammar == interactiveGrammar &&
        other.immersionMode == immersionMode &&
        other.definitions == definitions &&
        other.autoIGC == autoIGC &&
        other.audioWords == audioWords &&
        other.audioChoices == audioChoices &&
        other.audioOnNewMessage == audioOnNewMessage &&
        other.audioOnMessageClick == audioOnMessageClick &&
        other.enableAutocorrectChoice == enableAutocorrectChoice &&
        other.showDeveloperOptions == showDeveloperOptions &&
        other.listenFirst == listenFirst;
  }

  @override
  int get hashCode => Object.hashAll([
    interactiveTranslator.hashCode,
    interactiveGrammar.hashCode,
    immersionMode.hashCode,
    definitions.hashCode,
    autoIGC.hashCode,
    audioWords.hashCode,
    audioChoices.hashCode,
    audioOnNewMessage.hashCode,
    audioOnMessageClick.hashCode,
    enableAutocorrectChoice.hashCode,
    showDeveloperOptions.hashCode,
    listenFirst.hashCode,
  ]);
}

/// A wrapper around the matrix account data for the user profile.
/// Enables easy access to the profile data and saving new data.
class Profile {
  final UserSettings userSettings;
  final UserToolSettings toolSettings;
  final InstructionSettings instructionSettings;

  const Profile({
    required this.userSettings,
    this.toolSettings = const UserToolSettings(),
    this.instructionSettings = const InstructionSettings(),
  });

  /// Load an instance of profile from the client's account data.
  static Profile? fromAccountData(Map<String, Object?>? profileData) {
    if (profileData == null) return null;

    final userSettingsContent = profileData[UserConstants.userSettings];
    if (userSettingsContent == null) return null;

    final toolSettingsContent = profileData[UserConstants.toolSettings];
    final instructionSettingsContent =
        profileData[UserConstants.instructionsSettings];

    return Profile(
      userSettings: UserSettings.fromJson(
        userSettingsContent as Map<String, dynamic>,
      ),
      toolSettings: toolSettingsContent != null
          ? UserToolSettings.fromJson(
              toolSettingsContent as Map<String, dynamic>,
            )
          : UserToolSettings(),
      instructionSettings: instructionSettingsContent != null
          ? InstructionSettings.fromJson(
              instructionSettingsContent as Map<String, dynamic>,
            )
          : InstructionSettings(),
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = {
      UserConstants.userSettings: userSettings.toJson(),
      UserConstants.toolSettings: toolSettings.toJson(),
      UserConstants.instructionsSettings: instructionSettings.toJson(),
    };
    return json;
  }

  /// Migrate data from the old matrix account data
  /// format to the new matrix account data format.
  static Profile? migrateFromAccountData() {
    final userSettings = UserSettings.migrateFromAccountData();
    if (userSettings == null) return null;

    final toolSettings = UserToolSettings.migrateFromAccountData();
    final instructionSettings = InstructionSettings.migrateFromAccountData();
    return Profile(
      userSettings: userSettings,
      toolSettings: toolSettings,
      instructionSettings: instructionSettings,
    );
  }

  /// Saves the current configuration of the profile to the client's account data.
  /// If [waitForDataInSync] is true, the function will wait for the updated account
  /// data to come through in a sync, indicating that it has been set on the matrix server.
  Future<void> saveProfileData({bool waitForDataInSync = false}) async {
    final PangeaController pangeaController = MatrixState.pangeaController;
    final Client client = pangeaController.matrixState.client;
    final List<String> profileKeys = [
      UserConstants.userSettings,
      UserConstants.toolSettings,
      UserConstants.instructionsSettings,
    ];

    Future<SyncUpdate>? waitForUpdate;
    if (waitForDataInSync) {
      waitForUpdate = client.onSync.stream.firstWhere(
        (sync) =>
            sync.accountData != null &&
            sync.accountData!.any(
              (event) => event.content.keys.any((k) => profileKeys.contains(k)),
            ),
      );
    }
    await client.setAccountData(
      client.userID!,
      UserConstants.userProfile,
      toJson(),
    );

    if (waitForDataInSync) {
      await waitForUpdate;
    }
  }

  static Profile get emptyProfile {
    return Profile(
      userSettings: UserSettings(),
      toolSettings: UserToolSettings(),
      instructionSettings: InstructionSettings(),
    );
  }

  /// Autocorrect, resolved for this device and the learner's current target
  /// language: the explicit choice if they've made one, otherwise the
  /// platform default — layering in the one case that default doesn't
  /// already cover on its own. [UserToolSettings.enableAutocorrectPlatformDefault]
  /// is already unconditionally true on Android (the composer redirects the
  /// keyboard itself) and unconditionally false on iOS; here, an iOS device
  /// that has been observed typing with a matching keyboard also resolves
  /// true. See target-language-keyboard.instructions.md, "When autocorrect
  /// turns on".
  bool get effectiveAutocorrect =>
      toolSettings.enableAutocorrectChoice ??
      (UserToolSettings.enableAutocorrectPlatformDefault ||
          ObservedKeyboardStore.hasObservedKeyboard(
            userSettings.targetLanguage,
          ));

  /// Clears [updated]'s autocorrect choice when its target language differs
  /// from [previous]'s — a choice made for one target language says nothing
  /// about the next (target-language-keyboard.instructions.md, "When
  /// autocorrect turns on"). A no-op when the target language is unchanged.
  static Profile resetAutocorrectIfLanguageChanged(
    Profile previous,
    Profile updated,
  ) {
    if (updated.userSettings.targetLanguage ==
        previous.userSettings.targetLanguage) {
      return updated;
    }
    return updated.copyWith(
      toolSettings: updated.toolSettings.copyWith(
        setEnableAutocorrectNull: true,
      ),
    );
  }

  /// The autocorrect choice a settings page should show while a target
  /// language selection is still pending Save.
  ///
  /// A pending change to a different language clears the choice, matching
  /// what [resetAutocorrectIfLanguageChanged] will do on save. The case that
  /// needs care is the round trip: selecting another language and then
  /// coming back before Save leaves the language unchanged overall, so a
  /// choice cleared on the way out has to come back, or the cleared value is
  /// what gets persisted and a choice the learner never revisited is
  /// silently lost. [clearedByLanguageChange] distinguishes that from a
  /// choice the learner deliberately toggled this session, which is left
  /// alone.
  static bool? pendingAutocorrectChoice({
    required String? savedLanguage,
    required bool? savedChoice,
    required bool? pendingChoice,
    required String? selectedLanguage,
    required bool clearedByLanguageChange,
  }) {
    if (selectedLanguage != savedLanguage) return null;
    return clearedByLanguageChange ? savedChoice : pendingChoice;
  }

  Profile copyWith({
    UserSettings? userSettings,
    UserToolSettings? toolSettings,
    InstructionSettings? instructionSettings,
  }) {
    return Profile(
      userSettings: userSettings ?? this.userSettings,
      toolSettings: toolSettings ?? this.toolSettings,
      instructionSettings: instructionSettings ?? this.instructionSettings,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Profile &&
        other.userSettings == userSettings &&
        other.toolSettings == toolSettings &&
        other.instructionSettings == instructionSettings;
  }

  @override
  int get hashCode =>
      userSettings.hashCode ^
      toolSettings.hashCode ^
      instructionSettings.hashCode;
}

/// Model of data from pangea chat server. Not used anymore, in favor of matrix account data.
/// This class if used to read in data from the server to be migrated to matrix account data.
class PangeaProfile {
  final String createdAt;
  final String pangeaUserId;
  String? dateOfBirth;
  String? targetLanguage;
  String? sourceLanguage;

  String? country;
  bool? publicProfile;

  PangeaProfile({
    required this.createdAt,
    required this.pangeaUserId,
    this.dateOfBirth,
    this.targetLanguage,
    this.sourceLanguage,
    this.country,
    this.publicProfile,
  });

  factory PangeaProfile.fromJson(Map<String, dynamic> json) {
    final l2 = LanguageModel.codeFromNameOrCode(json[ModelKey.targetLanguage]);
    final l1 = LanguageModel.codeFromNameOrCode(json[ModelKey.sourceLanguage]);

    return PangeaProfile(
      createdAt: json[UserConstants.userCreatedAt],
      pangeaUserId: json[UserConstants.userPangeaUserId],
      dateOfBirth: json[UserConstants.userDateOfBirth],
      targetLanguage: l2,
      sourceLanguage: l1,
      publicProfile: json[UserConstants.publicProfile],
      country: json[UserConstants.userCountry],
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data[UserConstants.userCreatedAt] = createdAt;
    data[UserConstants.userPangeaUserId] = pangeaUserId;
    data[UserConstants.userDateOfBirth] = dateOfBirth;
    data[ModelKey.targetLanguage] = targetLanguage;
    data[ModelKey.sourceLanguage] = sourceLanguage;
    data[UserConstants.publicProfile] = publicProfile;
    data[UserConstants.userCountry] = country;
    return data;
  }
}

class PangeaProfileResponse {
  final PangeaProfile profile;
  final String access;

  PangeaProfileResponse({required this.profile, required this.access});

  factory PangeaProfileResponse.fromJson(Map<String, dynamic> json) {
    return PangeaProfileResponse(
      profile: PangeaProfile.fromJson(json[UserConstants.userProfile]),
      access: json[UserConstants.userAccess],
    );
  }
}
