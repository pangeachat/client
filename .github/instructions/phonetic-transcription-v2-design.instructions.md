---
applyTo: "lib/pangea/phonetic_transcription/**,lib/pangea/text_to_speech/**, lib/**"
---

# Phonetic Transcription — v2 Migration Design

## 1. Overview

Phonetic transcription provides pronunciations for L2 tokens, tailored to the user's L1. Applies to **all L1/L2 combinations** — not just non-Latin scripts (e.g., Spanish "lluvia" → "YOO-vee-ah" for an English L1 speaker).

For v2, `showTranscription` returns `true` unconditionally (script-difference gate removed). The property is kept in place.

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
| Response | Deeply nested, single pronunciation, no IPA | Flat `pronunciations` array, each with `transcription`, `tts_phoneme`, `ud_conditions` |
| Disambiguation | None | `ud_conditions` (e.g. `Pos=ADV`, `Pos=VERB`) |
| Server caching | None | CMS-backed (subsequent calls are instant) |

- `lang_code`: language of the token (may differ from `user_l2` for loanwords/code-switching).
- `user_l2`: included in base schema but does not affect pronunciation — only `lang_code` and `user_l1` matter.

**Response example** (Chinese — `tts_phoneme` uses pinyin):
```json
{
  "pronunciations": [
    { "transcription": "hái", "tts_phoneme": "hai2", "ud_conditions": "Pos=ADV" },
    { "transcription": "huán", "tts_phoneme": "huan2", "ud_conditions": "Pos=VERB" }
  ]
}
```

**Response example** (Spanish — `tts_phoneme` uses IPA):
```json
{
  "pronunciations": [
    { "transcription": "YOO-vee-ah", "tts_phoneme": "ˈʎubja", "ud_conditions": null }
  ]
}
```

### `tts_phoneme` Format by Language

The PT v2 handler selects the correct phoneme format based on `lang_code`. The client treats `tts_phoneme` as an opaque string — it never needs to know the alphabet.

| `lang_code` | Phoneme format | `alphabet` (resolved by TTS server) | Example |
|---|---|---|---|
| `cmn-CN`, `cmn-TW`, `zh` | Pinyin + tone numbers | `pinyin` | `hai2` |
| `yue` (Cantonese) | Jyutping + tone numbers | `jyutping` | `sik6 faan6` |
| `ja` | Yomigana (hiragana) | `yomigana` | `なか` |
| All others | IPA | `ipa` | `ˈʎubja` |

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

If disambiguation doesn't produce a single match, **display all pronunciations** (e.g. `"hái / huán"`), each with its own play button for TTS using its `tts_phoneme` (see §5).

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

## 5. TTS with Phoneme Pronunciation

PT covers **isolated words** only. Whole-message audio uses the existing TTS flow (unaffected).

### Problem
Ambiguous surface forms (e.g., 还 → hái vs huán) get arbitrary pronunciation from device TTS because it has no context.

### Decision Flow

The branch point is **how many entries are in the PT v2 `pronunciations` array** for this word.

```
PT response has 1 pronunciation? (unambiguous word)
  → YES: Use surface text for TTS as today (device or server fallback).
         Device TTS will pronounce it correctly — no phoneme override needed.
  → NO (2+ pronunciations — heteronym):
     Can disambiguate to exactly one using UD context? (§3)
       → YES: Send that pronunciation's tts_phoneme to _speakFromChoreo.
       → NO:  Send first pronunciation's tts_phoneme to _speakFromChoreo as default,
              or let user tap a specific pronunciation to play its tts_phoneme.
```

**The TTS request always contains at most one `tts_phoneme` string.** Disambiguation happens *before* calling TTS.

### Implementation

**PT v2 handler** (choreo):
1. Rename `ipa` → `tts_phoneme` in the `Pronunciation` schema.
2. LLM prompt instructions produce the correct phoneme format based on `lang_code`:
   - Chinese (`zh`, `cmn-CN`, `cmn-TW`): pinyin with tone numbers (e.g. `hai2`)
   - Cantonese (`yue`): jyutping with tone numbers (e.g. `sik6`)
   - Japanese (`ja`): yomigana in hiragana (e.g. `なか`)
   - All others: IPA (e.g. `ˈʎubja`)
3. Eval function validates format matches expected type for the language.

**TTS server** (choreo):
1. Add `tts_phoneme: Optional[str] = None` to `TextToSpeechRequest`.
2. Resolve the SSML `alphabet` from `lang_code` (see table in §2). Client never sends the alphabet.
3. When `tts_phoneme` is set, wrap text in `<phoneme alphabet="{resolved}" ph="{tts_phoneme}">{text}</phoneme>` inside existing SSML `<speak>` tags.
4. Include `tts_phoneme` in cache key.

**Client**:
1. Rename `ipa` → `ttsPhoneme` in `TextToSpeechRequestModel` and `DisambiguationResult`.
2. Rename `ipa` → `ttsPhoneme` param in `TtsController.tryToSpeak` and `_speakFromChoreo`.
3. When `ttsPhoneme` is provided, skip device TTS and call `_speakFromChoreo`.
4. When `ttsPhoneme` is not provided, behavior unchanged.
5. Client treats `ttsPhoneme` as an opaque string — no language-specific logic needed.

### Cache-Only Phoneme Resolution

`TtsController.tryToSpeak` resolves `ttsPhoneme` from the **local PT v2 cache** (`_resolveTtsPhonemeFromCache`) rather than making a server call. This is a deliberate tradeoff:

- **Why cache-only**: TTS is latency-sensitive — adding a blocking PT v2 network call before every word playback would degrade the experience. By the time a user taps to play a word, the PT v2 response has almost certainly already been fetched and cached (it was needed to render the transcription overlay).
- **What if the cache misses**: The word plays without phoneme override, using device TTS or plain server TTS. This is the same behavior as before PT v2 existed — acceptable because heteronyms are ~5% of words. The user still gets audio, just without guaranteed disambiguation.
- **No silent failures**: A cache miss doesn't block or error — it falls through gracefully.

---

## 6. Status

### Choreo — Complete (PR #1700, CMS PR #131)

- ✅ PT v2 handler, schemas, document, router, constants
- ✅ `tts_phoneme` rename (`ipa` → `tts_phoneme`) in PT v2 + TTS schemas
- ✅ SSML `<phoneme>` wrapping with per-language alphabet resolution
- ✅ Duration fallback for Google TTS (suppresses timepoints inside `<phoneme>` tags)
- ✅ CMS migration applied (`ipa` → `tts_phoneme` column rename)
- ✅ All unit + integration tests pass

### Client — Models & Plumbing Complete, UI Integration In Progress

- ✅ `Pronunciation` model with `ttsPhoneme` field (`pt_v2_models.dart`)
- ✅ Disambiguation logic (`pt_v2_disambiguation.dart`)
- ✅ `PTV2Repo` calling v2 endpoint with sync cache lookup
- ✅ `TextToSpeechRequestModel` with `ttsPhoneme`
- ✅ `TtsController` — `_resolveTtsPhonemeFromCache`, auto-resolve in `tryToSpeak`
- ✅ `showTranscription` returns `true` unconditionally
- ⬜ **Legacy v1 cleanup**: `PhoneticTranscriptionRepo` (v1) still exists — verify no callers remain, then delete
- ⬜ **UI testing**: Verify PT v2 renders correctly in chat (WordZoomWidget) and analytics (VocabDetailsView)
- ⬜ **Heteronym TTS testing**: Verify phoneme-driven TTS plays correct pronunciation for disambiguated heteronyms (e.g., 还 as hái vs huán)
- ⬜ **Local caching**: Verify 24-hour TTL, disk cache, logout cleanup (`phonetic_transcription_storage` in `_storageKeys`)

