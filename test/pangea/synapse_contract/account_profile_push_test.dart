@Timeout(Duration(minutes: 3))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics/client_analytics_extension.dart';
import 'package:fluffychat/features/analytics_access/access_notice_extension.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/notifications/notifications_client_extension.dart';
import 'package:fluffychat/features/notifications/notifications_settings_model.dart';
import 'package:fluffychat/features/user/analytics_profile_model.dart';
import 'package:fluffychat/features/user/own_profile_client_extension.dart';
import 'package:fluffychat/features/user/pangea_push_rules_extension.dart';
import 'package:fluffychat/features/user/public_profile_model.dart';
import 'package:fluffychat/features/user/user_constants.dart';
import 'package:fluffychat/features/user/user_model.dart' as pangea_user;
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/onboarding/onboarding_client_extension.dart';
import 'package:fluffychat/routes/onboarding/onboarding_settings_model.dart';
import '../endpoint_test_env.dart';
import 'contract_harness.dart';

/// Phase 2, part 2 — account data, push rules, and profile contracts
/// (client#8574).
void main() {
  if (!EndpointTestEnv.available) {
    test(
      'synapse contract suite is local-only',
      () {},
      skip: 'requires client/.env',
    );
    return;
  }

  late Client client;

  setUpAll(() async {
    await ContractHarness.initTestEnvironment();
    client = await ContractHarness.loggedIn('contract-p2-app-a');
  });

  tearDownAll(() async {
    await ContractHarness.dispose(client);
  });

  Future<Map<String, Object?>> accountData(String type) =>
      client.getAccountData(client.userID!, type);

  group('custom account-data types', () {
    test('analytics-access notice pending → accepted', () async {
      await client.setAccessNoticePending('!p2-course:example.test');
      var data = await accountData(PangeaEventTypes.accessNoticeShown);
      expect(
        (data['notices_accepted'] as Map?)?['!p2-course:example.test'],
        false,
        reason: 'pending is recorded as an explicit false',
      );

      await client.setAccessNoticeAccepted('!p2-course:example.test');
      data = await accountData(PangeaEventTypes.accessNoticeShown);
      expect(
        (data['notices_accepted'] as Map?)?['!p2-course:example.test'],
        true,
      );
    });

    test('onboarding settings persist', () async {
      await client.setShowedTrialPage();
      final data = await accountData(PangeaEventTypes.onboardingSettings);
      // Exact key: the persona is reused across runs, so isNotEmpty would be
      // vacuously green from run 2 even if the write no-oped or renamed.
      expect(
        data,
        const OnboardingSettingsModel(showedTrialPage: true).toJson(),
        reason: 'onboarding progress must persist byte-equal',
      );
    });

    test('notification settings write the serializer shape', () async {
      // Flip relative to the LOCAL cached value — that is what the
      // extension's equality early-return actually compares against, so
      // flipping from anything else risks a skipped write.
      final current = client.notificationSettings.enableEmailNotifs;
      final model = NotificationsSettingsModel(enableEmailNotifs: !current);

      await client.setNotificationsSettings(model);

      final data = await accountData(PangeaEventTypes.notificationSettings);
      expect(data, model.toJson());
    });

    test('the p.user_profile bundle round-trips through the parser', () async {
      // Profile.saveProfileData is MatrixState-coupled, so this writes the
      // PRODUCTION serializer's output directly (Profile.toJson emits
      // several explicit JSON nulls — the part an account-data normalizer
      // would most plausibly strip) and pins the parser as the read side.
      final profile = pangea_user.Profile(
        userSettings: pangea_user.UserSettings(
          targetLanguage: 'es',
          sourceLanguage: 'en',
          createdAt: DateTime.utc(2026),
        ),
      );
      final payload = profile.toJson();
      await client.setAccountData(
        client.userID!,
        UserConstants.userProfile,
        payload,
      );

      final data = await accountData(UserConstants.userProfile);
      expect(
        data,
        payload,
        reason:
            'the bundle must round-trip byte-equal, explicit nulls included',
      );
      final parsed = pangea_user.Profile.fromAccountData(data);
      expect(parsed?.userSettings.targetLanguage, 'es');
    });
  });

  group('push rules', () {
    test('the named override rules and the analytics-room mute land', () async {
      // A fresh persona with an analytics room: setPangeaPushRules mutes
      // analytics rooms per-room and installs the two named override rules.
      final learner = await ContractHarness.loggedIn(
        'contract-p2-push-${DateTime.now().millisecondsSinceEpoch}',
      );
      addTearDown(() => ContractHarness.dispose(learner));
      final analyticsRoom = (await learner.getMyAnalyticsRoom(
        LanguageModel(langCode: 'es', displayName: 'Spanish'),
      ))!;
      ContractHarness.trackRoom(learner, analyticsRoom.id);

      await learner.setPangeaPushRules();

      // Server truth via the raw pushrules read, not the cached sync copy.
      final raw = await learner.request(
        RequestType.GET,
        '/client/v3/pushrules/',
      );
      final global = raw['global'] as Map<String, Object?>;

      final overrides = (global['override'] as List).cast<Map>();
      final analyticsInvite = overrides
          .where((r) => r['rule_id'] == PangeaEventTypes.analyticsInviteRule)
          .firstOrNull;
      expect(
        analyticsInvite,
        isNotNull,
        reason: 'the analytics-invite suppression rule must exist',
      );
      expect(
        (analyticsInvite?['conditions'] as List?)
            ?.map((c) => (c as Map)['key'])
            .toList(),
        containsAll(['type', 'content.reason']),
        reason: 'the custom condition keys are the contract',
      );

      final tts = overrides
          .where((r) => r['rule_id'] == PangeaEventTypes.textToSpeechRule)
          .firstOrNull;
      expect(tts, isNotNull, reason: 'the TTS suppression rule must exist');
      expect(
        (tts?['conditions'] as List?)?.map((c) => (c as Map)['key']).toList(),
        containsAll([
          'content.msgtype',
          'content.transcription.lang_code',
          'content.transcription.text',
        ]),
        reason:
            'dotted-path conditions into the Pangea transcription payload — '
            'the shape most exposed to push-condition validation changes',
      );

      // The SDK's dontNotify writes an OVERRIDE rule keyed by the room id
      // with empty actions and a room_id event_match condition — pin that
      // exact shape (it is what a server-side push-rule validation change
      // would break).
      final analyticsMute = overrides
          .where((r) => r['rule_id'] == analyticsRoom.id)
          .firstOrNull;
      expect(
        analyticsMute,
        isNotNull,
        reason: 'the analytics room must be muted via a room-scoped override',
      );
      expect(analyticsMute?['actions'], isEmpty);
      expect(
        (analyticsMute?['conditions'] as List?)?.single,
        allOf(
          containsPair('kind', 'event_match'),
          containsPair('key', 'room_id'),
          containsPair('pattern', analyticsRoom.id),
        ),
      );
    });
  });

  group('profile writes', () {
    Future<Map<String, Object?>> rawProfile() async => await client.request(
      RequestType.GET,
      '/client/v3/profile/${Uri.encodeComponent(client.userID!)}',
    );

    test(
      'displayname and avatar orchestration incl. the empty-string clear',
      () async {
        final name = 'P2 Contract ${DateTime.now().millisecondsSinceEpoch}';
        await client.setOwnDisplayName(name);
        expect((await rawProfile())['displayname'], name);

        await client.setOwnAvatarUrl(
          Uri.parse('mxc://local.pangea.chat/p2contract'),
        );
        expect(
          (await rawProfile())['avatar_url'],
          'mxc://local.pangea.chat/p2contract',
        );

        // The clear contract: Synapse rejects null, so the client writes an
        // EMPTY STRING — pin that the server accepts and stores it.
        await client.setOwnAvatar(null);
        final cleared = (await rawProfile())['avatar_url'];
        expect(
          cleared,
          anyOf(isNull, ''),
          reason: 'clearing must not 400 and must remove the avatar',
        );
      },
    );

    test('the MSC4133 extended analytics-profile field round-trips', () async {
      // The production serializer, analytics_room_id included — a Matrix
      // room id nested two levels inside an extended profile field is the
      // value most exposed to MSC4133 content validation.
      final lang = LanguageModel(langCode: 'es', displayName: 'Spanish');
      final payload = PublicProfileModel(
        analytics: AnalyticsProfileModel(
          targetLanguage: lang,
          languageAnalytics: {
            lang: LanguageAnalyticsProfileEntry(
              3,
              120,
              analyticsRoomId: '!p2analytics:${client.userID!.split(':').last}',
            ),
          },
        ),
        country: 'MX',
      ).toJson();
      await client.setUserProfile(
        client.userID!,
        PangeaEventTypes.profileAnalytics,
        payload,
      );

      final profile = await rawProfile();
      expect(
        profile[PangeaEventTypes.profileAnalytics],
        payload,
        reason:
            'the non-spec extended profile field must survive — the surface '
            'the leaderboard and analytics-access resolution read',
      );
    });
  });

  group('SMTP-dependent auth route contracts', () {
    // Same treatment as phase 1's requestToken test: the route must exist
    // and accept the request shape; mail delivery is not asserted locally.
    test('password-reset token route exists', () async {
      try {
        await client.requestTokenToResetPasswordEmail(
          'p2-secret-${DateTime.now().millisecondsSinceEpoch}',
          'p2-reset@example.com',
          1,
        );
      } on MatrixException catch (e) {
        expect(
          e.error,
          isNot(MatrixError.M_UNRECOGNIZED),
          reason: 'the password-reset token route must exist',
        );
      } on Exception catch (e) {
        // ONLY the opaque non-JSON 5xx of an SMTP-less stack is tolerated —
        // a socket failure, HTML 404, or parse error must stay red.
        expect(
          e.toString(),
          contains('http error response'),
          reason: 'unexpected failure shape: $e',
        );
      }
    });

    test('3pid email token route exists', () async {
      try {
        await client.requestTokenToRegisterEmail(
          'p2-secret-${DateTime.now().millisecondsSinceEpoch}',
          'p2-3pid@example.com',
          1,
        );
      } on MatrixException catch (e) {
        expect(
          e.error,
          isNot(MatrixError.M_UNRECOGNIZED),
          reason: 'the 3pid email token route must exist',
        );
      } on Exception catch (e) {
        // Same tolerance as above: only the opaque 5xx shape.
        expect(
          e.toString(),
          contains('http error response'),
          reason: 'unexpected failure shape: $e',
        );
      }
    });
  });
}
