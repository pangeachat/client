// The merged call recording on a SLOW LINK (client#9825).
//
// After a 1:1 call the app mixes both people's halves into one
// `pangea.call_audio_merged` recording and uploads it. The coordinator used to
// race every stage, the upload included, against a 60 s stage timeout -- so on
// a link where a ~2 MB upload takes longer than that, the attempt was given up,
// the `mxc://` that landed afterwards was dropped, and the whole merge was
// downloaded, mixed and uploaded again on the next pass. The recording arrived
// many minutes late (or never) and left orphan uploads behind.
//
// This scenario reproduces that link and reads the outcome off the WIRE and
// the SERVER, never the screen:
//
//   - every POST to the media upload endpoint, from both browsers, with its
//     start, its end, the mxc it returned and the stored size;
//   - the merged event for THIS call (relations on the call key), with its
//     server timestamp.
//
// WHO MERGES. `decideCallAudioMerge` ranks the half writers by
// (senderId, deviceId), and the rank-r device waits `baseBackoff * r` (30 s)
// before trying. So the account whose user id sorts first merges, and the other
// one steps in 30 s later if no merged event has shown up. With a 90 s upload
// the second device WOULD step in -- on any build -- and mask the coordinator
// behaviour under test (it would upload its own merge, unthrottled). So by
// default, once both halves are on the server, the scenario throttles the
// rank-0 browser's uploads and KILLS the rank-1 browser (SIGKILL, h.kill): the
// peer closed the app after the call, the merging device is on a slow link.
// MERGE_KILL_PEER=0 keeps the peer alive (then two uploads are the election's
// doing, not the coordinator's).
//
// WHEN THE THROTTLE GOES ON. After both halves are on the server, not before
// the hang-up: each half is itself a ~2 MB upload of the whole call, with its
// own size-scaled deadline, and throttling it would test the half writer
// instead. The merger waits an 8 s settle from the newest half before it even
// downloads, so the throttle is in place well before the merged upload starts
// -- and a check FAILS if a merged upload began before it.
//
// Settings (environment):
//   MERGE_TALK_SEC     how long the call runs (default 70: ~2.2 MB at 16 kHz mono)
//   MERGE_UPLOAD_BPS   upload throughput on the merging browser, bytes/s
//                      (default 24000, ~90 s for 2.2 MB; 0 = no throttle)
//   MERGE_KILL_PEER    1 (default when throttled) kills the rank-1 browser
//   MERGE_WATCH_SEC    give up waiting for the merged event after this long
//                      (default 900 throttled, 300 unthrottled)
//   MERGE_LINGER_SEC   keep watching the wire after the merged event, to catch
//                      a duplicate upload (default 120)
//
// Every check fails when it cannot be asked: a run that never reached a
// throttled merged upload has not proved anything about one.
const fs = require('fs');
const h = require('./harness');
const { ui, mx, wait } = h;
const { room: ROOM, roomId: ROOM_ID, shot } = h.cfg;

const CALL_AUDIO = 'pangea.call_audio';
const MERGED = 'pangea.call_audio_merged';
const STAGE_TIMEOUT_MS = 60000;
const FIXTURE_LANG = 'en';

const num = (name, dflt) => {
  const v = process.env[name];
  return v === undefined || v === '' ? dflt : Number(v);
};
const TALK_SEC = num('MERGE_TALK_SEC', 70);
const UPLOAD_BPS = num('MERGE_UPLOAD_BPS', 24000);
const THROTTLED = UPLOAD_BPS > 0;
const KILL_PEER = num('MERGE_KILL_PEER', THROTTLED ? 1 : 0) === 1;
const WATCH_SEC = num('MERGE_WATCH_SEC', THROTTLED ? 900 : 300);
const LINGER_SEC = num('MERGE_LINGER_SEC', 120);

const UPLOAD_PATH = /\/_matrix\/(media\/(v3|r0|v1)|client\/v1\/media)\/upload(\?|$)/;
const filenameOf = (url) => {
  try {
    return new URL(url).searchParams.get('filename') || '';
  } catch (_) {
    return '';
  }
};

const T0 = Date.now();
const rel = (t) => (t == null ? '-' : `+${((t - T0) / 1000).toFixed(1)}s`);
const evidence = [];
function say(line) {
  const stamped = `${new Date().toISOString()} ${line}`;
  evidence.push(stamped);
  console.log(`   ${stamped}`);
}

/// Every media upload this page puts on the wire, and its console lines about
/// merging. Installed before the app loads (openParticipant's `prepare`).
function watch(name, uploads, consoleLog) {
  return async (page) => {
    page.on('request', (req) => {
      if (req.method() !== 'POST' || !UPLOAD_PATH.test(req.url())) return;
      const u = {
        who: name,
        filename: filenameOf(req.url()),
        url: req.url(),
        startedAt: Date.now(),
        finishedAt: null,
        failedAt: null,
        status: null,
        mxc: null,
        error: null,
      };
      uploads.push(u);
      req.__merge = u;
      say(`UPLOAD-START ${name} ${u.filename} ${req.url().replace(/^https?:\/\/[^/]+/, '')}`);
    });
    page.on('requestfinished', async (req) => {
      const u = req.__merge;
      if (!u) return;
      u.finishedAt = Date.now();
      const res = req.response();
      u.status = res ? res.status() : null;
      try {
        const body = JSON.parse(await res.text());
        u.mxc = body.content_uri || null;
      } catch (e) {
        u.error = `could not read the response: ${e.message}`;
      }
      say(`UPLOAD-END   ${name} ${u.filename} status=${u.status} `
        + `took=${((u.finishedAt - u.startedAt) / 1000).toFixed(1)}s mxc=${u.mxc}`);
    });
    page.on('requestfailed', (req) => {
      const u = req.__merge;
      if (!u) return;
      u.failedAt = Date.now();
      u.error = req.failure() ? req.failure().errorText : 'failed';
      say(`UPLOAD-FAIL  ${name} ${u.filename} after `
        + `${((u.failedAt - u.startedAt) / 1000).toFixed(1)}s: ${u.error}`);
    });
    page.on('console', (m) => {
      const t = m.text();
      if (/merge|call audio|call_audio|upload/i.test(t)) {
        consoleLog.push(`${new Date().toISOString()} [${name}] ${t.slice(0, 400)}`);
      }
    });
  };
}

async function refuseIfNotLearning(names) {
  for (const name of names) {
    const a = h.cfg.accounts[name];
    const { token, userId } = await mx.login(a.user, a.pass);
    let code;
    try {
      code = await mx.targetLanguage(token, userId);
    } finally {
      await mx.logout(token);
    }
    if (mx.baseLang(code) !== FIXTURE_LANG) {
      throw new Error(`${name} (${userId}) is learning ${code || 'nothing'}; `
        + `the fixtures are ${FIXTURE_LANG} -- set the learning language first`);
    }
  }
}

/// Every event of [relType] related to [callKey], read off the server's
/// relations index -- scoped by the call key itself rather than by a window of
/// the timeline that can age out.
async function related(token, callKey, relType) {
  const out = [];
  let from = null;
  for (let i = 0; i < 10; i++) {
    const q = `limit=50${from ? `&from=${encodeURIComponent(from)}` : ''}`;
    const r = await mx.api(
      `/_matrix/client/v1/rooms/${encodeURIComponent(ROOM_ID)}/relations/`
        + `${encodeURIComponent(callKey)}/${encodeURIComponent(relType)}?${q}`,
      { token },
    );
    out.push(...(r.chunk || []));
    if (!r.next_batch) break;
    from = r.next_batch;
  }
  return out.filter((e) => e.type === relType && e.content?.call_key === callKey);
}

/// The stored size of an upload, asked of the media repo.
async function storedSize(token, mxc) {
  const m = /^mxc:\/\/([^/]+)\/(.+)$/.exec(mxc || '');
  if (!m) return null;
  const res = await fetch(
    `${h.cfg.homeserver}/_matrix/client/v1/media/download/${m[1]}/${m[2]}`,
    { headers: { authorization: `Bearer ${token}` } },
  );
  if (!res.ok) return `HTTP ${res.status}`;
  return (await res.arrayBuffer()).byteLength;
}

async function main() {
  const s = 'merge_slow_link';
  console.log(`[0] settings: talk ${TALK_SEC}s, upload ${THROTTLED ? `${UPLOAD_BPS} B/s` : 'unthrottled'}, `
    + `kill peer ${KILL_PEER}, watch ${WATCH_SEC}s, linger ${LINGER_SEC}s`);
  h.refuseIfAnotherRunIsLive();
  await refuseIfNotLearning(['learner', 'calltester']);

  const uploads = [];
  const consoleLog = [];
  console.log('[1] two browsers');
  const A = await h.openParticipant('learner', ROOM, 9741,
    { prepare: watch('learner', uploads, consoleLog) });
  const B = await h.openParticipant('calltester', ROOM, 9742,
    { prepare: watch('calltester', uploads, consoleLog) });
  const byUser = { [A.userId]: A, [B.userId]: B };
  const mA = await h.mark(A.token, ROOM_ID);

  console.log('[2] a call');
  const rang = await h.actUntil(
    'place call',
    async () => {
      await h.ensureRoom(A, ROOM);
      await ui.clickControl(A.page, 'call').catch(() => {});
    },
    async () => (await h.since(A.token, ROOM_ID, mA)).some(
      (e) => e.type === mx.RING && e.sender === A.userId,
    ),
    { tries: 4, gap: 4000 },
  );
  h.check(s, 'placing a call rang the other side', rang, 'no ring event reached the room');
  if (!rang) { h.report(); process.exit(2); }
  const joined = await h.actUntil(
    'answer',
    () => ui.clickBanner(B.page, 'answer'),
    () => mx.hasMembership(B.token, ROOM_ID, B.userId),
  );
  h.check(s, 'answering joined the call', joined, 'the callee never published a membership');
  if (!joined) { h.report(); process.exit(2); }
  say(`CALL-ANSWERED talking ${TALK_SEC}s`);
  await wait(TALK_SEC * 1000);

  console.log('[3] hang up');
  const left = await h.actUntil(
    'hangup',
    () => ui.clickPanel(A.page, 'hangup'),
    async () => !(await mx.hasMembership(A.token, ROOM_ID, A.userId)),
  );
  const tHang = Date.now();
  say(`HANGUP confirmed=${left} at ${new Date(tHang).toISOString()}`);
  h.check(s, 'hanging up left the call', left, 'the caller still holds a membership');

  console.log('[4] both halves on the server, then the slow link');
  let halves = [];
  let callKey = null;
  for (let i = 0; i < 90; i++) {
    const evs = (await h.since(A.token, ROOM_ID, mA)).filter((e) => e.type === CALL_AUDIO);
    const keys = new Set(evs.map((e) => e.content?.call_key));
    if (keys.size === 1) {
      callKey = [...keys][0];
      halves = await related(A.token, callKey, CALL_AUDIO);
      if (new Set(halves.map((e) => e.sender)).size >= 2) break;
    }
    await wait(1000);
  }
  const senders = [...new Set(halves.map((e) => e.sender))].sort();
  for (const e of halves) {
    say(`HALF ${e.event_id} sender=${e.sender} device=${e.content?.device_id} `
      + `size=${e.content?.size} duration_ms=${e.content?.duration_ms} `
      + `ts=${new Date(e.origin_server_ts).toISOString()} url=${e.content?.url}`);
  }
  h.check(s, 'both people wrote a recording half for this call', senders.length === 2,
    `${halves.length} half/halves from [${senders.join(', ')}] under call key ${callKey}`);
  if (senders.length !== 2 || !callKey) { h.report(); process.exit(1); }

  // The election, recomputed the way decideCallAudioMerge does: the half writer
  // whose (senderId, deviceId) sorts first is rank 0.
  const merger = byUser[senders[0]];
  const peer = byUser[senders[1]];
  h.check(s, 'the elected merger is one of the two browsers', !!merger && !!peer,
    `senders ${senders.join(', ')} vs browsers ${A.userId}, ${B.userId}`);
  if (!merger || !peer) { h.report(); process.exit(1); }
  say(`ELECTION rank0 (merges first) = ${merger.name} ${merger.userId}; rank1 = ${peer.name}`);

  let tThrottle = null;
  if (THROTTLED) {
    await merger.page.emulateNetworkConditions({
      offline: false,
      download: -1,
      upload: UPLOAD_BPS,
      latency: 0,
    });
    tThrottle = Date.now();
    say(`THROTTLE ${merger.name} upload=${UPLOAD_BPS} B/s download=unlimited`);
  }
  if (KILL_PEER) {
    await h.kill(peer);
    say(`KILLED ${peer.name} (SIGKILL) so it cannot step in as rank 1`);
  }

  console.log('[5] watching the wire and the room');
  const mergedUploads = () => uploads.filter((u) => u.filename === 'call_audio_merged.wav');
  let merged = [];
  let tMergedSeen = null;
  const deadline = tHang + WATCH_SEC * 1000;
  let lingerUntil = null;
  let lastNote = 0;
  for (;;) {
    const now = Date.now();
    if (lingerUntil ? now > lingerUntil : now > deadline) break;
    if (!tMergedSeen) {
      merged = await related(A.token, callKey, MERGED).catch(() => []);
      if (merged.length) {
        tMergedSeen = Date.now();
        lingerUntil = tMergedSeen + LINGER_SEC * 1000;
        for (const e of merged) {
          say(`MERGED-EVENT ${e.event_id} sender=${e.sender} `
            + `ts=${new Date(e.origin_server_ts).toISOString()} `
            + `(+${((e.origin_server_ts - tHang) / 1000).toFixed(1)}s after hang-up) `
            + `size=${e.content?.size} url=${e.content?.url}`);
        }
      }
    }
    if (now - lastNote > 60000) {
      lastNote = now;
      say(`WATCH +${((now - tHang) / 1000).toFixed(0)}s since hang-up: `
        + `${mergedUploads().length} merged upload(s) so far, merged event ${tMergedSeen ? 'seen' : 'not yet'}`);
    }
    await wait(2000);
  }
  // Re-read once more at the end: the count of merged events, not just the first.
  merged = await related(A.token, callKey, MERGED).catch(() => merged);

  console.log('[6] evidence');
  const mu = mergedUploads();
  for (const u of mu) {
    const size = u.mxc ? await storedSize(A.token, u.mxc).catch((e) => e.message) : null;
    u.size = size;
    say(`MERGED-UPLOAD ${u.who} started=${rel(u.startedAt)} (+${((u.startedAt - tHang) / 1000).toFixed(1)}s after hang-up) `
      + `finished=${rel(u.finishedAt)} failed=${rel(u.failedAt)} `
      + `took=${u.finishedAt ? ((u.finishedAt - u.startedAt) / 1000).toFixed(1) + 's' : 'unfinished'} `
      + `status=${u.status} mxc=${u.mxc} stored_bytes=${size}${u.error ? ` error=${u.error}` : ''}`);
  }
  for (const e of merged) {
    say(`MERGED-EVENT-FINAL ${e.event_id} sender=${e.sender} ts=${new Date(e.origin_server_ts).toISOString()} `
      + `(+${((e.origin_server_ts - tHang) / 1000).toFixed(1)}s after hang-up) url=${e.content?.url} size=${e.content?.size}`);
  }

  console.log('[7] checks');
  const first = mu[0];
  h.check(s, 'a merged upload went out on the wire', !!first,
    `no POST with filename=call_audio_merged.wav from either browser in ${WATCH_SEC}s`);
  if (THROTTLED) {
    h.check(s, 'the throttle was on before the first merged upload began',
      !!first && tThrottle != null && first.startedAt >= tThrottle,
      first ? `first merged upload started ${rel(first.startedAt)}, throttle ${rel(tThrottle)}` : 'no merged upload');
    // The precondition the bug needs: without it a green run proves nothing.
    const held = first
      ? ((first.finishedAt || first.failedAt || Date.now()) - first.startedAt)
      : 0;
    h.check(s, 'the throttled merged upload outlasted the 60 s stage timeout',
      held > STAGE_TIMEOUT_MS,
      `the first merged upload took ${(held / 1000).toFixed(1)}s -- the throttle did not slow it `
        + 'past the stage timeout, so this run cannot say anything about it');
  }
  h.check(s, 'exactly ONE merged-file upload for the call', mu.length === 1,
    `${mu.length} merged uploads: ${mu.map((u) => `${u.who}@${rel(u.startedAt)}->${u.mxc}`).join(', ')}`);
  h.check(s, 'a merged recording event arrived for the call', merged.length >= 1,
    `no ${MERGED} related to ${callKey} within ${WATCH_SEC}s of hang-up`);
  h.check(s, 'exactly one merged recording event', merged.length === 1,
    `${merged.length} merged events`);
  const ev = merged[0];
  h.check(s, "the merged event references that upload's mxc",
    !!ev && !!first && ev.content?.url === first.mxc,
    `event url ${ev?.content?.url} vs upload mxc ${first?.mxc}`);
  const uploadMs = first && first.finishedAt ? first.finishedAt - first.startedAt : 0;
  const budgetMs = 120000 + (THROTTLED ? uploadMs : 0);
  h.check(s, 'the merged event arrived within 2 min of hang-up plus the upload time',
    !!ev && ev.origin_server_ts - tHang <= budgetMs,
    ev
      ? `arrived ${((ev.origin_server_ts - tHang) / 1000).toFixed(1)}s after hang-up; budget ${(budgetMs / 1000).toFixed(1)}s`
      : 'no merged event to time');
  if (THROTTLED) {
    h.check(s, 'the merged file is big enough for the bug (>= 1.5 MB)',
      !!ev && Number(ev.content?.size) >= 1.5e6,
      `merged size ${ev?.content?.size}`);
  }
  h.check(s, `${merger.name} (the merger) had no unhandled errors`, merger.errors.length === 0,
    JSON.stringify(merger.errors.slice(0, 3)));

  const base = `merge_slow_link-${THROTTLED ? 'throttled' : 'plain'}-${T0}`;
  fs.writeFileSync(shot(`${base}-evidence.log`), evidence.join('\n') + '\n');
  fs.writeFileSync(shot(`${base}-console.log`), consoleLog.join('\n') + '\n');
  console.log(`   evidence: ${shot(`${base}-evidence.log`)}`);
  console.log(`   console:  ${shot(`${base}-console.log`)}`);

  const bad = h.report();
  for (const p of [A, B]) {
    if (p !== peer || !KILL_PEER) await p.browser.close().catch(() => {});
  }
  process.exit(bad === 0 ? 0 : 1);
}

main().catch(async (e) => {
  console.error('FAILED', e && e.stack ? e.stack : e);
  process.exit(1);
});
