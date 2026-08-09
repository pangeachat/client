# streaming_supported_langs — D5 byte-shared language contract (KD-8), client copy

`supported_streaming_languages.json` is a **byte-identical copy** of the choreo source of truth at
`2-step-choreographer/app/handlers/speech_to_text/streaming/__tests__/streaming_supported_langs/`.
It is the sorted set of short language codes the D3 routing table routes to a live streaming
provider. The client streaming gate (`StreamingSttGate.supportedLangCodesShort`) is finalized to
this set, and `supported_langs_contract_test.dart` pins the gate set to these JSON bytes (D5).

**Never hand-edit.** Widen ONLY by regenerating the pack from the choreo table and copying both
`supported_streaming_languages.json` + `MANIFEST.sha256` here byte-for-byte in the SAME change.
The cross-repo `cmp`/sha256 gate (T9) fails on any drift between the choreo bytes and this copy.

`MANIFEST.sha256` pins ONLY `supported_streaming_languages.json` (sha256 + two spaces + filename).
