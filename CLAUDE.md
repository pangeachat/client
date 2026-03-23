Check the relevant `.github/instructions/` doc before and after coding. If it doesn't exist, create it with the user first. Follow [instructions-authoring.instructions.md](../../.github/instructions/instructions-authoring.instructions.md) for doc standards.

# client - Flutter/Dart Language Learning Chat App

## Tech Stack
- **Framework**: Flutter (SDK ≥3.0), Dart
- **GitHub**: `pangeachat/client` (fork of `krille-chan/fluffychat`, package name `fluffychat`)
- **Protocol**: Matrix Client-Server API via `matrix` Dart SDK
- **Subscriptions**: RevenueCat
- **Backend**: 2-step-choreographer (FastAPI) via `PApiUrls`
- **Error Tracking**: Sentry
- **Routing**: GoRouter

## Quick Reference

### Project Structure
- `lib/pages/`, `lib/widgets/`, `lib/utils/`, `lib/config/` — FluffyChat base code
- `lib/pangea/` — **All Pangea language-learning code** (~30 feature modules)
- `pangea_packages/` — Shared isolate packages
- Pangea modifications in FluffyChat files marked with `// #Pangea` ... `// Pangea#`

### Key Files
- **Entry point**: `lib/main.dart`
- **Root state**: `lib/widgets/matrix.dart` (`MatrixState`)
- **Pangea controller**: `lib/pangea/common/controllers/pangea_controller.dart`
- **Routes**: `lib/config/routes.dart`
- **API URLs**: `lib/pangea/common/network/urls.dart`
- **HTTP client**: `lib/pangea/common/network/requests.dart`
- **Environment**: `lib/pangea/common/config/environment.dart` (reads `.env` / `config.sample.json`)
- **Event types**: `lib/pangea/events/constants/pangea_event_types.dart`
- **Choreographer**: `lib/pangea/choreographer/choreographer.dart`

### Conventions
- Package imports use `package:fluffychat/...`
- Feature modules follow pattern: `models/`, `repo/` (API calls), `widgets/`, `utils/`, `constants/`
- API repo files pair with request/response models (e.g., `igc_repo.dart` + `igc_request_model.dart` + `igc_response_model.dart`)
- Controllers extend `ChangeNotifier` or use `BaseController<T>` (stream-based)

## Feature Docs

Read the relevant doc before coding in that area:

- [analytics-system.instructions.md](.github/instructions/analytics-system.instructions.md) — Analytics System (`lib/pangea/analytics_data/**,lib/pangea/analytics_misc/**,lib/pangea/analytics_page/**,lib/pangea/analytics_summary/**,lib/pangea/analytics_practice/**,lib/pangea/analytics_settings/**,lib/pangea/analytics_downloads/**,lib/pangea/analytics_details_popup/**,lib/pangea/space_analytics/**,lib/pangea/constructs/**`)
- [conversation-activities.instructions.md](.github/instructions/conversation-activities.instructions.md) — Activity System (`lib/pangea/activity_planner/**,lib/pangea/activity_sessions/**,lib/pangea/activity_suggestions/**,lib/pangea/activity_summary/**`)
- [course-plans.instructions.md](.github/instructions/course-plans.instructions.md) — Course Plans — Client Design (`lib/pangea/course_plans/**,lib/pangea/course_creation/**,lib/pangea/course_chats/**`)
- [cross-service-debugging.instructions.md](.github/instructions/cross-service-debugging.instructions.md) — Cross-Service Debugging (client) (`**/assets/.env*,**/*repo*.dart,lib/pangea/common/network/**`)
- [deployment.instructions.md](.github/instructions/deployment.instructions.md) — Deployment (client) (`**/.github/workflows/**,**/deploy*`)
- [events-and-tokens.instructions.md](.github/instructions/events-and-tokens.instructions.md) — Events & Tokens — Matrix Event Data Model (`lib/pangea/events/**,lib/pangea/extensions/**`)
- [grammar-analytics.instructions.md](.github/instructions/grammar-analytics.instructions.md) — Grammar Analytics — Design & Intent (`lib/pangea/morphs/**, lib/pangea/constructs/**, lib/pangea/analytics_details_popup/morph_*`)
- [invite-by-email.instructions.md](.github/instructions/invite-by-email.instructions.md) — Invite by Email — Client (`lib/pangea/course_creation/**,lib/pangea/join_codes/**,lib/pangea/spaces/**`)
- [joining-courses.instructions.md](.github/instructions/joining-courses.instructions.md) — Joining Courses — Client Design (`lib/pangea/join_codes/**,lib/pangea/chat_list/**,lib/pangea/course_creation/**,lib/pangea/spaces/**,lib/pages/chat_list/**,lib/utils/url_launcher.dart,lib/config/routes.dart`)
- [language-list.instructions.md](.github/instructions/language-list.instructions.md) — Language List — Client (`lib/pangea/languages/**,lib/pangea/learning_settings/**,lib/pangea/login/pages/language_selection_page.dart`)
- [layout.instructions.md](.github/instructions/layout.instructions.md) — Client Layout System (`lib/config/themes.dart,lib/widgets/layouts/**,lib/pangea/spaces/space_navigation_column.dart,lib/widgets/navigation_rail.dart,lib/config/routes.dart`)
- [matrix-auth.instructions.md](.github/instructions/matrix-auth.instructions.md) — Matrix Auth — Staging Test Tokens (`**/.env,**/assets/.env*`)
- [modules.instructions.md](.github/instructions/modules.instructions.md) — Pangea Feature Modules (`lib/pangea/`) (`lib/pangea/**`)
- [phonetic-transcription-v2-design.instructions.md](.github/instructions/phonetic-transcription-v2-design.instructions.md) — Phonetic Transcription v2 Design (`lib/pangea/phonetic_transcription/**,lib/pangea/text_to_speech/**, client/controllers/tts_controller.dart`)
- [playwright-testing.instructions.md](.github/instructions/playwright-testing.instructions.md) — Playwright Testing — Flutter Web Client (`lib/pangea/**,lib/pages/**,lib/widgets/**`)
- [practice-exercises.instructions.md](.github/instructions/practice-exercises.instructions.md) — Practice Exercises (`lib/pangea/practice_activities/**,lib/pangea/analytics_practice/**,lib/pangea/toolbar/message_practice/**`)
- [profile.instructions.md](.github/instructions/profile.instructions.md) — Profile Settings — Architecture & Contracts (`lib/pangea/user/user_model.dart, lib/pangea/user/user_controller.dart, lib/pangea/user/public_profile_model.dart, lib/pangea/user/analytics_profile_model.dart, lib/pangea/chat_settings/utils/bot_client_extension.dart, lib/pangea/chat_settings/models/bot_options_model.dart, lib/pangea/bot/utils/bot_room_extension.dart, lib/pangea/bot/widgets/bot_chat_settings_dialog.dart, lib/pangea/learning_settings/**, lib/pangea/common/controllers/pangea_controller.dart`)
- [returning-user-detection.instructions.md](.github/instructions/returning-user-detection.instructions.md) — Returning User Detection — Preventing Duplicate Accounts (`lib/pangea/login/**,lib/pangea/authentication/**,lib/pages/login/**`)
- [subscriptions.instructions.md](.github/instructions/subscriptions.instructions.md) — Subscription Module — Client (`lib/pangea/subscription/**`)
- [testing.instructions.md](.github/instructions/testing.instructions.md) — Testing Guide (Client) (`**/*test*,**/test/**,**/integration_test/**`)
- [token-info-feedback-v2.instructions.md](.github/instructions/token-info-feedback-v2.instructions.md) — Token Info Feedback — v2 Migration (Client) (`lib/pangea/token_info_feedback/**`)
- [toolbar-reading-assistance.instructions.md](.github/instructions/toolbar-reading-assistance.instructions.md) — Toolbar & Reading Assistance (`lib/pangea/toolbar/**`)
- [writing-assistance.instructions.md](.github/instructions/writing-assistance.instructions.md) — Writing Assistance — Design & Architecture (`lib/pangea/choreographer/**`)
