---
applyTo: "lib/pangea/phonetic_transcription/**,lib/pangea/text_to_speech/**"
---

# Phonetic Transcription — v2 Migration Design

## 1. Overview

Phonetic transcription provides pronunciations for L2 tokens, tailored to the user's L1. Applies to **all L1/L2 combinations** — not just non-Latin scripts (e.g., Spanish "lluvia" → "YOO-vee-ah" for an English L1 speaker).

For v2, make `showTranscription` return `true` unconditionally (remove the script-difference gate). Keep the property in place.

> **TODO**: Verify UI/UX at each `showTranscription` use site — some may need layout adjustments.

## 2. v1 → v2 Changes

### Architecture (unchanged)
```
PhoneticTranscriptionWidget → PhoneticTranscriptionBuilder → PhoneticTranscriptionRepo
```

### Endpoint & Models

| Aspect | v1 | v2 |
|--------|----|----|
| Endpoint | `POST /choreo/phonetic_transcription` | `POST /choreo/phonetic_transcription_v2` |
| Request | `arc` (LanguageArc) + `content` (PangeaTokenText) | `surface` (string) + `lang_code` + `user_l1` + `user_l2` |
| Response | Deeply nested, single pronunciation, no IPA | Flat `pronunciations` array, each with `transcription`, `ipa`, `ud_conditions` |
| Disambiguation | None | `ud_conditions` (e.g. `Pos=ADV`, `Pos=VERB`) |
| Server caching | None | CMS-backed (subsequent calls are instant) |

- `lang_code`: language of the token (may differ from `user_l2` for loanwords/code-switching).
- `user_l2`: included in base schema but does not affect pronunciation — only `lang_code` and `user_l1` matter.

**Response example**:
```json
{
  "pronunciations": [
    { "transcription": "hái", "ipa": "xaɪ̌", "ud_conditions": "Pos=ADV" },
    { "transcription": "huán", "ipa": "xwaň", "ud_conditions": "Pos=VERB" }
  ]
}
```

> **⚠ Choreo fix**: `pt-migration` branch prompt uses `POS=ADV` (all-caps key). Must be corrected to **PascalCase**: `Pos=ADV`, `Tense=Past`, etc.

### Deployment Order

1. **Choreo first**: Ship v2 endpoint. v1 stays up.
2. **Client second**: Switch to v2, remove v1 code.
3. Client PR can assume v2 is already deployed — no feature flags needed.

---

## 3. Disambiguation Logic

When the server returns multiple pronunciations (heteronyms), the client chooses which to display based on UD context.

### 3.1 Chat Page (WordZoomWidget)

Available context: `token.pos`, `token._morph` (full morph features), `token.text.content`.

**`lang_code` source**: `PangeaMessageEvent.messageDisplayLangCode` — the detected language of the text, not always `user_l2`.

**Strategy**: Match `ud_conditions` against all available UD info (POS + morph features).

### 3.2 Analytics Page (VocabDetailsView)

Available context: `constructId.lemma`, `constructId.category` (lowercased POS).

**`lang_code`**: Always `userL2Code`.

**Surface**: Use the **lemma** as `surface` in the PT request (dictionary pronunciation). Remove audio buttons beside individual forms — users access form pronunciation in chat.

**Strategy**: Match `ud_conditions` against lemma + POS only. Compare case-insensitively (`category` is lowercased, `ud_conditions` uses uppercase).

### 3.3 Fallback

If disambiguation doesn't produce a single match, **display all pronunciations** (e.g. `"hái / huán"`), each with its own play button for TTS (see §5).

### 3.4 Parsing `ud_conditions`

Keys use **PascalCase** (`Pos`, `Tense`, `VerbForm`). Parse:
1. Split on `;` → individual conditions.
2. Split each on `=` → feature-value pairs.
3. `Pos=X` → compare against `token.pos` (or `constructId.category`, case-insensitively).
4. Other features → compare against `token.morph`.
5. A pronunciation matches if **all** conditions are satisfied.
6. `null` `ud_conditions` = unconditional (unambiguous word).

---

## 4. Local Caching

- **Key**: `surface + lang_code + user_l1`. Exclude `user_l2` (doesn't affect pronunciation). Exclude UD context (full pronunciation list is cached; disambiguation at display time).
- **Memory cache**: In-flight deduplication + fast reads, short TTL (keep ~10 min).
- **Disk cache**: `GetStorage`, **24-hour TTL** (down from 7 days — server CMS cache means re-fetching is cheap, daily refresh ensures corrections propagate).
- **Invalidation**: Lazy eviction on read.
- **Logout**: Add PT storage key to `_storageKeys` in `pangea_controller.dart` (`phonetic_transcription_storage` is currently missing).
- **v1 migration**: Not needed — v1 entries use a different key format (request hashCode) and expire naturally at 7-day TTL.

---

## 5. TTS with IPA Fallback

PT covers **isolated words** only. Whole-message audio uses the existing TTS flow (unaffected).

### Problem
Ambiguous surface forms (e.g., 还 → hái vs huán) get arbitrary pronunciation from device TTS because it has no context.

### Decision Flow
```
1 pronunciation in response?
  → YES: Use surface text for TTS as today (device or server fallback).
  → NO (ambiguous):
     Can disambiguate to one? (§3)
       → YES: Force _speakFromChoreo with that pronunciation's IPA.
       → NO:  Force _speakFromChoreo with first IPA as default,
              or let user tap a specific pronunciation to play it.
```

### Implementation

**Choreo**:
1. Add `ipa: Optional[str] = None` to `TextToSpeechRequestModel`.
2. When set, wrap text in `<phoneme alphabet="ipa" ph="{ipa}">{text}</phoneme>` inside existing SSML `<speak>` tags.
3. Include `ipa` in CMS cache key.
4. Graceful fallback — `<phoneme>` only works with certain Google Cloud TTS voices (Neural2, Studio).

**Client**:
1. Add `String? ipa` to `TextToSpeechRequestModel`, serialize in `toJson()`.
2. Add optional `ipa` param to `TtsController.tryToSpeak` and `_speakFromChoreo`.
3. When `ipa` is provided, skip device TTS and call `_speakFromChoreo`.
4. When `ipa` is not provided, behavior unchanged.

---

## 6. Resolved & Open Items

### Resolved
- **Morph feature format**: PascalCase keys (`Pos`, `Tense`, `VerbForm`). `ConstructIdentifier.category` is lowercased — compare case-insensitively.
- **Choreo prompt fix**: `POS=ADV` → `Pos=ADV` on `pt-migration` branch.
- **TTS IPA**: Server already uses SSML. Add `ipa` field; server wraps in `<phoneme>` tags (§5).
- **Cache migration**: v1 entries orphaned (different key format), expire at 7-day TTL. No migration.
- **Cache clearing on logout**: PT storage missing from `_storageKeys` — add it.
- **Analytics form audio**: Remove form-level audio buttons. Use lemma as surface for PT.
- **`lang_code` source**: Chat = `messageDisplayLangCode` (detected, not always `user_l2`). Analytics = `userL2Code`. Both correct.
- **Token info feedback**: v2 copy of endpoint, not in-place edit. Full plan in dedicated docs:
  - **Server**: `2-step-choreographer/.github/instructions/token-info-feedback-pt-v2.instructions.md`
  - **Client**: `client/.github/instructions/token-info-feedback-v2.instructions.md`

### Open
1. **Google Cloud TTS `<phoneme>` voice support**: Verify current voices support it, or add fallback.
2. **`_storageKeys` gap**: Broader cleanup (7+ missing containers) tracked by ggurdin. This PR: just add `phonetic_transcription_storage`.
