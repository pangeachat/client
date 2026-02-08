# Client Documentation Index

Read individual files only when working on the relevant area.

## Available Documentation

| Document                                     | Purpose                                           | Read When                                                     |
| -------------------------------------------- | ------------------------------------------------- | ------------------------------------------------------------- |
| [modules.md](modules.md)                     | Map of all `lib/pangea/` feature modules          | Finding where code lives, understanding module boundaries     |
| [choreographer.md](choreographer.md)         | Writing assistance flow (IGC, IT, text editing)   | Working on grammar check, interactive translation, span cards |
| [events-and-tokens.md](events-and-tokens.md) | Custom Matrix events, token model, event wrappers | Reading/writing Matrix events, token data, representations    |

## Quick Module Lookup (No Doc Read Needed)

| Module                 | One-liner                                                                |
| ---------------------- | ------------------------------------------------------------------------ |
| `common/`              | Shared infra: `PangeaController`, `PApiUrls`, `Environment`, HTTP client |
| `choreographer/`       | Writing assistance — IGC + IT + text editing                             |
| `toolbar/`             | Message toolbar — reading assistance, word cards, practice               |
| `events/`              | Custom Matrix event types and token models                               |
| `extensions/`          | `PangeaRoomExtension` and other Room extensions                          |
| `languages/`           | Language models, store, locale provider                                  |
| `lemmas/`              | Dictionary-form word data and UI                                         |
| `morphs/`              | Morphological analysis (POS, features)                                   |
| `constructs/`          | Learning construct tracking                                              |
| `practice_activities/` | Practice activity generation                                             |
| `activity_sessions/`   | Structured activity sessions in rooms                                    |
| `analytics_data/`      | Local analytics DB, sync, updates                                        |
| `user/`                | User profile, settings, push rules                                       |
| `subscription/`        | RevenueCat subscription management                                       |
| `spaces/`              | Matrix Spaces (courses) extensions                                       |
| `course_plans/`        | CMS course plan models                                                   |
| `chat_settings/`       | Room-level bot/language settings                                         |
| `learning_settings/`   | User learning preferences UI                                             |
| `payload_client/`      | CMS API client                                                           |
| `translation/`         | Full-text translation                                                    |
| `speech_to_text/`      | STT integration                                                          |
| `text_to_speech/`      | TTS integration                                                          |
| `token_info_feedback/` | Token-level user feedback                                                |
| `login/`               | Pangea signup/login flow                                                 |
