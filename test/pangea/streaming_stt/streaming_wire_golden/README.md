# Frozen neutral D4 relay-frame golden pack

These five `wire_*.json` files are the **byte-shared source of truth** for the
provider-neutral relay->client wire (D4). A **byte-identical** copy lives in the
client at `test/pangea/streaming_stt/streaming_wire_golden/`. Any change here
must be copied to the client in the SAME change (mirrors the `stt_golden/`
"copy to all repos in the same change" policy) or the cross-repo contract test
fails.

Each frame is exactly what `normalize_deepgram_raw(<captured raw>)` yields for
the corresponding captured Deepgram frame in `../deepgram_raw_fixtures/`, plus
the relay-generated error frame:

| golden file | source | neutral `type` |
|---|---|---|
| `wire_partial.json` | `results_partial.json` | `partial` |
| `wire_segment_final.json` | `results_segment_final.json` | `segment_final` |
| `wire_stream_final.json` | `results_stream_final.json` | `stream_final` |
| `wire_speech_boundary.json` | `utterance_end.json` | `speech_boundary` |
| `wire_error.json` | `error_message("upstream_error")` | `error` |

`MANIFEST.sha256` pins ONLY the five data files (never itself, never this
README). Regenerate the pack from the real normalizer output — do not
hand-edit the frames. `test_streaming_wire_golden.py` verifies the SHA-256
integrity AND that each frame still equals the live normalizer output on the
captured raw frames.
