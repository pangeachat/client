// A SUBSCRIBED caller reads the UNSUBSCRIBED callee's side (#8792).
//
// `transcript.js` proves each device writes its own half. It cannot prove the
// paid promise in voice-video-calls.instructions.md: when only one person on the
// call is subscribed, that person's client also produces the OTHER half from
// the recording the call saved, so the subscriber reads both sides. Unit tests
// passed for that and staging still showed one side, which is why this asks it
// of two real browsers on the local stack.
//
// PRECONDITION, settled outside this file because it is account state: the
// local choreo must resolve `learner` as subscribed and `calltester` as not
// (`GET /subscription/status`). The run refuses up front when it does not,
// rather than "passing" a call in which nobody was unsubscribed.
//
// What it asks, all from the SERVER except the Transcribe button:
//   1. the callee's own half is the empty one a missing subscription writes;
//   2. both devices recorded audio, and a merged manifest landed;
//   3. the caller's device wrote a half FOR the callee (spoken_by), with the
//      callee's words in it;
//   4. the caller's transcript screen offers no Transcribe button left over for
//      a half that is already produced, and the callee's screen stays locked.
//
// Every console line either browser logs is written beside the screenshots, so
// a failure can be read off the app's own account of what it did.
const fs = require('fs');
const h = require('./harness');
const labels = require('./labels');
const { ui, mx, wait } = h;

const { room: ROOM, roomId: ROOM_ID, shot } = h.cfg;
const TRANSCRIPT = 'pangea.call_transcript';
const CALL_AUDIO = 'pangea.call_audio';
const MERGED = 'pangea.call_audio_merged';
const CALLEE_SAYS = ['course', 'orange', 'quarter', 'gardens'];
const CHOREO = process.env.CHOREO_URL || 'http://localhost:8012';

function spoken(ev) {
  const segs = ev?.content?.segments;
  if (!Array.isArray(segs)) return '';
  return segs.map((s) => (s && typeof s.text === 'string' ? s.text : '')).join(' ');
}

function words(text) {
  return new Set(text.toLowerCase().split(/[^\p{L}\p{N}]+/u).filter((w) => w.length >= 4));
}

/// The content of a half with the words replaced by a count, so the log shows
/// the accounting the reader classifies without printing the transcript.
function accountingOf(ev) {
  if (!ev) return null;
  const { segments, ...rest } = ev.content || {};
  return { event_id: ev.event_id, sender: ev.sender, segments: Array.isArray(segments) ? segments.length : segments, ...rest };
}

/// Every event of [types] after [mark], read back far enough that a call's
/// thirty-odd membership events cannot push them out of the window.
async function eventsSince(token, mark, types) {
  const out = [];
  let from = null;
  for (let page = 0; page < 5; page++) {
    const r = await mx.messagesBack(token, ROOM_ID, { from, limit: 200 });
    const chunk = r.chunk || [];
    let hitMark = false;
    for (const e of chunk.slice().reverse()) {
      if (e.event_id === mark) { hitMark = true; break; }
      if (types.includes(e.type)) out.push(e);
    }
    if (hitMark || !r.end || !chunk.length) break;
    from = r.end;
  }
  return out.reverse();
}

async function accessLevel(name) {
  const a = h.cfg.accounts[name];
  const { token } = await mx.login(a.user, a.pass);
  try {
    const r = await fetch(`${CHOREO}/subscription/status`, { headers: { authorization: `Bearer ${token}` } });
    return (await r.json()).access_level;
  } finally {
    await mx.logout(token);
  }
}

/// Opens the NEWEST call card's transcript. The timeline holds one for every
/// call the room has had and `ui.clickControl` can pick a months-old one, so
/// this clicks the lowest reachable card -- the same choice, and the same
/// reason, as `transcript_two_devices.js`.
async function openNewestTranscript(page) {
  const candidates = labels.candidates('transcriptLink');
  const nodes = (await ui.scan(page)).filter(
    (n) => n.hittable && n.names.some((name) => candidates.includes(name)),
  );
  if (!nodes.length) return false;
  const lowest = nodes.reduce((a, b) => (b.y > a.y ? b : a));
  await page.mouse.click(lowest.x, lowest.y);
  return true;
}

/// What each reader's transcript screen offers, read off the semantics tree:
/// the Transcribe button is a real control, so it is there or it is not.
async function readScreens(s, A, B, { expectProducedHalf }) {
  for (const p of [A, B]) {
    await h.ensureRoom(p, ROOM);
    await ui.enableSemantics(p.page).catch(() => {});
    await wait(3000);
    const opened = await openNewestTranscript(p.page).catch(() => false);
    h.check(s, `${p.name} opened the newest transcript`, opened, 'no transcript card on screen');
    await wait(6000);
    await ui.enableSemantics(p.page).catch(() => {});
    await p.page.screenshot({ path: shot(`peer-half-${p.name}.png`) }).catch(() => {});
  }
  const labelsA = await ui.labels(A.page).catch(() => []);
  const labelsB = await ui.labels(B.page).catch(() => []);
  console.log(`   A labels: ${JSON.stringify(labelsA.slice(0, 80))}`);
  console.log(`   B labels: ${JSON.stringify(labelsB.slice(0, 40))}`);
  const transcribeOnA = labelsA.includes('Transcribe');
  if (expectProducedHalf) {
    // The turns reach the semantics tree word by word, so B's words being
    // among A's labels is the screen drawing the produced half.
    const shown = new Set(labelsA.map((l) => l.toLowerCase()));
    h.check(s, "A's screen shows B's words", CALLEE_SAYS.some((w) => shown.has(w)),
      `none of ${CALLEE_SAYS.join('/')} on A's transcript screen`);
    h.check(s, 'A is offered no Transcribe button for a half already produced', !transcribeOnA,
      'a Transcribe button is still offered beside a produced half');
  } else {
    h.check(s, "A is offered Transcribe for B's unproduced half", transcribeOnA,
      'no Transcribe button on the subscribed reader\'s screen');
  }
  h.check(s, 'B (unsubscribed) sees the locked transcript', labelsB.includes('Unlock call transcript'),
    'no locked placeholder on the unsubscribed reader\'s screen');
  h.check(s, 'B (unsubscribed) is offered no Transcribe button', !labelsB.includes('Transcribe'),
    'the unsubscribed reader was offered on-demand transcription');
  return { labelsA, labelsB };
}

function recordConsole(p) {
  const lines = [];
  p.page.on('console', (m) => lines.push(`[${new Date().toISOString()}] ${m.type()} ${m.text()}`.slice(0, 2000)));
  return lines;
}

/// Exits with every browser closed: Chrome locks its profile, and a run that
/// leaves one open kills the next run at its first line.
async function finish(participants, code) {
  for (const p of participants) await p?.browser?.close().catch(() => {});
  process.exit(code);
}

async function main() {
  const s = 'peer-half';
  h.refuseIfAnotherRunIsLive();
  console.log('[0] who is subscribed');
  const subA = await accessLevel('learner');
  const subB = await accessLevel('calltester');
  console.log(`   learner=${subA} calltester=${subB}`);
  if (subA !== 'full' || subB !== 'none') {
    throw new Error('needs learner subscribed and calltester not; fix the local entitlements first');
  }

  if (process.env.PEER_HALF_REOPEN) {
    // Only the screens, for a call already made: what each reader is offered
    // once everything that call will ever write has landed.
    const A = await h.openParticipant('learner', ROOM, 9741);
    const B = await h.openParticipant('calltester', ROOM, 9742);
    // `produced` when that call's half for B already landed, anything else
    // when it has not.
    await readScreens(s, A, B, {
      expectProducedHalf: process.env.PEER_HALF_REOPEN === 'produced',
    });
    await finish([A, B], h.report() === 0 ? 0 : 1);
  }

  console.log('[1] two browsers');
  const A = await h.openParticipant('learner', ROOM, 9741);
  const B = await h.openParticipant('calltester', ROOM, 9742);
  const logA = recordConsole(A);
  const logB = recordConsole(B);
  const mA = await h.mark(A.token, ROOM_ID);

  console.log('[2] subscribed A calls unsubscribed B; both talk');
  const rang = await h.actUntil(
    'place call',
    async () => { await h.ensureRoom(A, ROOM); await ui.clickControl(A.page, 'call').catch(() => {}); },
    async () => (await h.since(A.token, ROOM_ID, mA)).some((e) => e.type === mx.RING && e.sender === A.userId),
    { tries: 4, gap: 4000 },
  );
  h.check(s, 'the call rang', rang, 'no ring event');
  if (!rang) { h.report(); await finish([A, B], 2); }
  const joined = await h.actUntil('answer', () => ui.clickBanner(B.page, 'answer'),
    () => mx.hasMembership(B.token, ROOM_ID, B.userId));
  h.check(s, 'B answered', joined, 'no callee membership');
  if (!joined) { h.report(); await finish([A, B], 2); }
  await wait(36000);

  console.log('[3] hang up');
  const left = await h.actUntil('hangup', () => ui.clickPanel(A.page, 'hangup'),
    async () => !(await mx.hasMembership(A.token, ROOM_ID, A.userId)));
  h.check(s, 'A left the call', left, 'A still holds a membership');

  console.log('[4] the halves, the recordings, the manifest, and any produced peer half');
  let halves = [];
  let peerHalf = null;
  // The backfill waits a jittered grace and retries discovery, so this waits
  // well past it for the half A produces for B.
  for (let i = 0; i < 50; i++) {
    halves = await eventsSince(A.token, mA, [TRANSCRIPT]);
    peerHalf = halves.find((e) => e.sender === A.userId && e.content?.spoken_by === B.userId);
    if (peerHalf) break;
    await wait(3000);
  }
  const audio = await eventsSince(A.token, mA, [CALL_AUDIO]);
  const merged = await eventsSince(A.token, mA, [MERGED]);
  const ownB = halves.find((e) => e.sender === B.userId && !e.content?.spoken_by);
  const ownA = halves.find((e) => e.sender === A.userId && !e.content?.spoken_by);
  const evidence = {
    halves: halves.map(accountingOf),
    audio: audio.map((e) => ({ event_id: e.event_id, sender: e.sender, ...e.content, url: e.content?.url ? 'mxc:...' : e.content?.url })),
    merged: merged.map((e) => ({ event_id: e.event_id, sender: e.sender, content: e.content })),
  };
  fs.writeFileSync(shot('peer-half-evidence.json'), JSON.stringify(evidence, null, 2));
  console.log(`   evidence -> ${shot('peer-half-evidence.json')}`);
  console.log(`   B's own half: ${JSON.stringify(accountingOf(ownB))}`);
  console.log(`   A's own half words: ${words(spoken(ownA)).size}`);
  console.log(`   call_audio senders: ${[...new Set(audio.map((e) => e.sender))].join(', ')}; merged: ${merged.length}`);

  h.check(s, "B's own half is the unsubscribed one", !!ownB
    && (ownB.content?.segments || []).length === 0
    && ownB.content?.chunks_refused_unsubscribed > 0,
  JSON.stringify(accountingOf(ownB)));
  h.check(s, 'both sides recorded audio', new Set(audio.map((e) => e.sender)).size >= 2,
    `${audio.length} call_audio from ${[...new Set(audio.map((e) => e.sender))].join(', ')}`);
  h.check(s, 'a merged manifest landed', merged.length >= 1, 'no pangea.call_audio_merged');
  const peerWords = CALLEE_SAYS.filter((w) => words(spoken(peerHalf)).has(w));
  h.check(s, "A's device produced B's half", !!peerHalf,
    'no pangea.call_transcript from A with spoken_by B');
  h.check(s, "the produced half carries B's words", peerWords.length > 0,
    `expected one of ${CALLEE_SAYS.join('/')}; got ${[...words(spoken(peerHalf))].slice(0, 12).join(' ')}`);

  console.log('[5] the screens');
  await readScreens(s, A, B, { expectProducedHalf: !!peerHalf });

  fs.writeFileSync(shot('peer-half-console-A.log'), logA.join('\n'));
  fs.writeFileSync(shot('peer-half-console-B.log'), logB.join('\n'));
  console.log(`   console -> ${shot('peer-half-console-A.log')}`);
  for (const p of [A, B]) {
    h.check(s, `${p.name} had no unhandled errors`, p.errors.length === 0, JSON.stringify(p.errors.slice(0, 3)));
  }
  await finish([A, B], h.report() === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error('FAILED', e && e.message ? e.message : e);
  process.exit(1);
});
