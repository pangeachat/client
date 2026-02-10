---
applyTo: "lib/pangea/phonetic_transcription/**,lib/pangea/text_to_speech/**, client/controllers/tts_controller.dart"
---

# Phonetic Transcription v2 Design

## 1. Overview

Phonetic transcription provides pronunciations for L2 tokens, tailored to the user's L1. Applies to **all L1/L2 combinations** — not just non-Latin scripts (e.g., Spanish "lluvia" → "YOO-vee-ah" for an English L1 speaker).

## 2. Endpoint & Models

### Endpoint

`POST /choreo/phonetic_transcription_v2`

### Request

`surface` (string) + `lang_code` + `user_l1` + `user_l2`

- `lang_code`: language of the token (may differ from `user_l2` for loanwords/code-switching).
- `user_l2`: included in base schema but does not affect pronunciation — only `lang_code` and `user_l1` matter.

### Response

Flat `pronunciations` array, each with `transcription`, `tts_phoneme`, `ud_conditions`. Server-cached via CMS (subsequent calls are instant).

**Response example** (Chinese — `tts_phoneme` uses pinyin):

```json
{
  "pronunciations": [
    {
      "transcription": "hái",
      "tts_phoneme": "hai2",
      "ud_conditions": "Pos=ADV"
    },
    {
      "transcription": "huán",
      "tts_phoneme": "huan2",
      "ud_conditions": "Pos=VERB"
    }
  ]
}
```

**Response example** (Spanish — `tts_phoneme` uses IPA):

```json
{
  "pronunciations": [
    {
      "transcription": "YOO-vee-ah",
      "tts_phoneme": "ˈʎubja",
      "ud_conditions": null
    }
  ]
}
```

### `tts_phoneme` Format by Language

The PT v2 handler selects the correct phoneme format based on `lang_code`. The client treats `tts_phoneme` as an opaque string — it never needs to know the alphabet.

| `lang_code`              | Phoneme format          | `alphabet` (resolved by TTS server) | Example      |
| ------------------------ | ----------------------- | ----------------------------------- | ------------ |
| `cmn-CN`, `cmn-TW`, `zh` | Pinyin + tone numbers   | `pinyin`                            | `hai2`       |
| `yue` (Cantonese)        | Jyutping + tone numbers | `jyutping`                          | `sik6 faan6` |
| `ja`                     | Yomigana (hiragana)     | `yomigana`                          | `なか`       |
| All others               | IPA                     | `ipa`                               | `ˈʎubja`     |

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
- **Logout**: PT storage keys registered in `_storageKeys` in `pangea_controller.dart` (both v1 `phonetic_transcription_storage` and v2 `phonetic_transcription_v2_storage`).

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

**The TTS request always contains at most one `tts_phoneme` string.** Disambiguation happens _before_ calling TTS.

### Implementation

**PT v2 handler** (choreo):

1. `tts_phoneme` on every `Pronunciation` — format determined by `lang_code`:
   - Chinese (`zh`, `cmn-CN`, `cmn-TW`): pinyin with tone numbers (e.g. `hai2`)
   - Cantonese (`yue`): jyutping with tone numbers (e.g. `sik6`)
   - Japanese (`ja`): yomigana in hiragana (e.g. `なか`)
   - All others: IPA (e.g. `ˈʎubja`)
2. Eval function validates format matches expected type for the language.

**TTS server** (choreo):

1. `tts_phoneme: Optional[str] = None` on `TextToSpeechRequest`.
2. Resolves SSML `alphabet` from `lang_code` (see table in §2). Client never sends the alphabet.
3. When `tts_phoneme` is set, wraps text in `<phoneme alphabet="{resolved}" ph="{tts_phoneme}">{text}</phoneme>` inside existing SSML `<speak>` tags.
4. `tts_phoneme` included in cache key.
5. Google Cloud TTS suppresses SSML mark timepoints inside `<phoneme>` tags → duration estimated via `estimate_duration_ms()`.

**Client**:

1. `ttsPhoneme` field on `TextToSpeechRequestModel` and `DisambiguationResult`.
2. `ttsPhoneme` param on `TtsController.tryToSpeak` and `_speakFromChoreo`.
3. When `ttsPhoneme` is provided, skips device TTS and calls `_speakFromChoreo`.
4. When `ttsPhoneme` is not provided, behavior unchanged.
5. Client treats `ttsPhoneme` as an opaque string — no language-specific logic needed.

### Cache-Only Phoneme Resolution

`TtsController.tryToSpeak` resolves `ttsPhoneme` from the **local PT v2 cache** (`_resolveTtsPhonemeFromCache`) rather than making a server call. This is a deliberate tradeoff:

- **Why cache-only**: TTS is latency-sensitive — adding a blocking PT v2 network call before every word playback would degrade the experience. By the time a user taps to play a word, the PT v2 response has almost certainly already been fetched and cached (it was needed to render the transcription overlay).
- **What if the cache misses**: The word plays without phoneme override, using device TTS or plain server TTS. This is the same behavior as before PT v2 existed — acceptable because heteronyms are ~5% of words. The user still gets audio, just without guaranteed disambiguation.
- **No silent failures**: A cache miss doesn't block or error — it falls through gracefully.

---

## 6. Future Improvements

- **Finetuning**: Once CMS accumulates enough examples, benchmark and train a smaller finetuned model on the server to replace `GPT_5_2`.
- **Legacy v1 endpoint removal**: The v1 `/choreo/phonetic_transcription` endpoint can be removed server-side once all clients are on v2.
