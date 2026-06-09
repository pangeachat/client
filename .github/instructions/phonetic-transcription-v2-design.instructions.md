---
applyTo: "lib/pangea/phonetic_transcription/**"
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

## 5. TTS Playback

PT covers **isolated words** only. PT's responsibility ends at producing a disambiguated `tts_phoneme` (§2–§3): the resulting TTS request carries **at most one** `tts_phoneme`, chosen _before_ playback. A word with a single pronunciation needs no override at all.

Everything about *speaking* the phoneme — routing the override to backend, cache-only resolution at playback time, and the backend's SSML phoneme rendering — is owned by the TTS feature ([word-text-to-speech.instructions.md](word-text-to-speech.instructions.md#phoneme-playback)) and the choreographer's [tts.instructions.md](../../../2-step-choreographer/.github/instructions/tts.instructions.md). Kept there as the single source so the playback flow doesn't drift across two docs.

---

## 6. Future Improvements

- **Finetuning**: Once CMS accumulates enough examples, benchmark and train a smaller finetuned model on the server to replace `GPT_5_2`.
- **Legacy v1 endpoint removal**: The v1 `/choreo/phonetic_transcription` endpoint can be removed server-side once all clients are on v2.
