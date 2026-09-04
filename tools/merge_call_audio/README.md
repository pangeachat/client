# merge_call_audio

Merges the two per-device `pangea.call_audio` halves of a Pangea call into
one recording, aligned on the SFU timeline, so a human can listen and judge
how natural the merged call sounds.

Pangea rooms are unencrypted, so a `pangea.call_audio` half is a plain
`mxc` download — there is no decryption step. This tool takes two already-local
plain audio files plus a small JSON manifest; fetching those files from the
room is a separate, earlier step done at test time.

## Command

```
./merge_call_audio --manifest halves.json --out ./out
```

With the clap fallback (see below):

```
./merge_call_audio --manifest halves.json --out ./out --clap-ms you=1200,friend=1350
```

Requires `ffmpeg`/`ffprobe` (tested against v8.1.1; looks on `PATH` first,
then falls back to `/opt/homebrew/bin/ffmpeg` and `/opt/homebrew/bin/ffprobe`)
and `jq`.

Run `./merge_call_audio --help` for the full flag list (`--sample-rate`,
`--ffmpeg`, `--ffprobe` overrides).

## Manifest

A JSON array of **exactly 2** objects, one per half:

```json
[
  {
    "sender": "@you:example.org",
    "label": "you",
    "file": "you.opus",
    "recording_started_offset_from_device_join_ms": 123,
    "device_joined_at_ms": 1735689000000,
    "sfu_joined_at_ms": 1735689000200
  },
  {
    "sender": "@friend:example.org",
    "label": "friend",
    "file": "friend.opus",
    "recording_started_offset_from_device_join_ms": 456,
    "device_joined_at_ms": 1735689000100,
    "sfu_joined_at_ms": 1735689000200
  }
]
```

| Field | Required | Notes |
|---|---|---|
| `label` | yes | short, unique name for the half; used in output and in `--clap-ms` |
| `file` | yes | path to the local audio file; relative paths resolve against the manifest's own directory, not the caller's cwd |
| `sender` | no | informational only (printed in the report); defaults to `unknown` |
| `recording_started_offset_from_device_join_ms` | for the primary method | ms from device join to this file's first sample |
| `device_joined_at_ms` | for the primary method | informational; not used in the delay formula directly, but expected alongside the other two stamps |
| `sfu_joined_at_ms` | for the primary method | absolute SFU-clock ms at which the device joined |
| `low_precision` | no | set `true` to force this half onto the `--clap-ms` fallback even if the three stamps above are present |

## Alignment math

On the SFU timeline, a half's audio starts at:

```
file_start_sfu_ms = sfu_joined_at_ms + recording_started_offset_from_device_join_ms
```

This is the absolute instant, in SFU-clock terms, that the half's file
begins. The half that started **earliest** (smallest `file_start_sfu_ms`)
needs no delay — it's already the earliest thing in the merge. The **other**
half is delayed (via ffmpeg's `adelay`) by the difference, so a
real-world-simultaneous sound (e.g. one person starts talking while the
other is still mid-word) lands on the same output sample in both tracks:

```
delay(earlier half) = 0
delay(later half)   = max(file_start_sfu_ms) - min(file_start_sfu_ms)
```

Double-check with a number: half A starts at SFU time 1000ms, half B at
1500ms. A real event at absolute SFU time 2000ms sits at local offset
1000ms in A's raw file and 500ms in B's. Delaying B by 500ms (not A) puts
that event at output position `0 + 1000 = 1000` for A and
`500 + 500 = 1000` for B — aligned. Delaying A instead would put it at
`500 + 1000 = 1500` for A vs `0 + 500 = 500` for B, which is *more*
misaligned than doing nothing. `selftest.sh` asserts the delay lands on the
correct half via a duration check that a min/max swap would flip (see the
comment above `PRIMARY_OK` in the script).

### Clap fallback

If either half is missing one of the three stamps above, or has
`"low_precision": true`, the tool refuses to guess with the primary method —
per-process alignment WARNs at run time and names exactly which stamp(s) are
missing for which half. Instead, pass `--clap-ms label=ms,label2=ms`: the ms
offset, within each **raw** file, of a shared audible transient both devices
recorded (e.g. both participants clap once near the start of the test call).
The half where the transient appears *later* in its own local time started
recording *sooner* (more lead-in before the clap), so the same min/max rule
applies with `-clap_ms` standing in for `file_start_sfu_ms`.

If the primary stamps are unusable and `--clap-ms` is not given (or doesn't
cover both labels), the tool exits non-zero rather than silently producing a
misaligned file.

## Outputs

Written to `--out`:

- `merged_stereo.wav` — half[0] (manifest array index 0) hard-left, half[1] hard-right, so each speaker is distinguishable.
- `merged_mono.wav` — `amix` of both halves, `normalize=1` to avoid clipping.

The tool also prints, per half: `file_start_sfu_ms` (or `clap_ms` in
fallback mode) and the applied `delay_ms`; each half's source duration with
a `WARN` if the two differ wildly (heuristic: more than 2s or 10% of the
shorter one, whichever is larger — a hint of drift, a dropped/rejoined
recorder, or mismatched files); and an `output_check` comparing the actual
merged duration against the expected one, which would `WARN` if the ffmpeg
graph ever stopped doing what the math above says it should.

That output-vs-expected check exists because of a real bug caught during
development: `amerge` (used for the stereo hard-L/R output) has no
`duration=longest` option — unlike `amix` — and silently truncates to
whichever delayed input ends first. Both delayed streams are explicitly
`apad`-ed to the shared target length before either `amerge` or `amix` sees
them; `--out`'s `output_check: ok` line is your confirmation that padding
actually took effect for a given run.

## Self-test

```
./selftest.sh
```

Generates two synthetic tone WAVs of **different, known durations** with a
**known** manifest-encoded start offset, runs the tool, and asserts:

- both outputs are produced;
- the printed delay matches the known offset, for both the timestamp method and the `--clap-ms` fallback (exercised in both directions, so the check isn't an artifact of which label happens to be first in the manifest);
- the delay landed on the *correct* half — via a duration check a min/max swap bug would flip, not just the printed number;
- missing stamps without `--clap-ms` refuse to run rather than guess;
- a missing audio file and a malformed manifest both fail loudly, naming the problem.

Last run: **16 passed, 0 failed**.
