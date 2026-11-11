// MOVING A CALL TO ANOTHER OF THE LEARNER'S DEVICES (client#9173).
//
// The other person calls; the learner answers on their FIRST device and
// talks; MOVE_AT_S seconds after the ring the learner opens the call on their
// SECOND device (the room's call button: it joins the call already under way),
// picks "Use this device", talks for TALK_AFTER_S, and hangs up.
//
// Asked of the SERVER afterwards, never of the clicks:
//   1. BOTH learner devices posted a recording (pangea.call_audio), and the
//      first one names the second as the device the call moved to.
//   2. BOTH learner devices posted a transcript half.
//   3. ONE full-call recording (pangea.call_audio_merged) that names every
//      recording of the call and says it is complete.
//   4. The learner's words from BEFORE the move (device one's fixture) and
//      AFTER it (device two's) are both in the learner's transcript.
//
// Run from the client root, one run at a time:
//   CALL_WORK_DIR=... MOVE_AT_S=150 node test/e2e/call_move.js
const h = require('./harness');
const { ui, mx, wait } = h;
const labels = require('./labels');

const { room: ROOM, roomId: ROOM_ID } = h.cfg;

const MOVE_AT_S = Number(process.env.MOVE_AT_S || 150);
const TALK_AFTER_S = Number(process.env.TALK_AFTER_S || 40);
const SETTLE_S = Number(process.env.SETTLE_S || 240);

const AUDIO = 'pangea.call_audio';
const MERGED = 'pangea.call_audio_merged';
const TRANSCRIPT = 'pangea.call_transcript';

const BEFORE_WORDS = ['compass', 'orchard', 'trumpet', 'glacier', 'pelican', 'saffron', 'marble', 'thunder'];
const AFTER_WORDS = ['lantern', 'bicycle', 'harbor', 'november', 'cinnamon', 'walnut', 'ferry', 'meadow'];

const s = 'call-move';
const opened = [];

async function relations(token, callKey, relType) {
  const out = [];
  let from = null;
  for (let page = 0; page < 10; page++) {
    const q = from ? `?from=${encodeURIComponent(from)}&limit=100` : '?limit=100';
    const res = await mx.api(
      `/_matrix/client/v1/rooms/${encodeURIComponent(ROOM_ID)}/relations/${encodeURIComponent(callKey)}/${relType}${q}`,
      { token },
    );
    out.push(...(res.chunk || []));
    if (!res.next_batch) break;
    from = res.next_batch;
  }
  return out;
}

const spoken = (ev) => (ev?.content?.segments || [])
  .map((seg) => (seg && typeof seg.text === 'string' ? seg.text : '')).join(' ').toLowerCase();

const hits = (text, words) => words.filter((w) => text.includes(w));

async function finish(code) {
  for (const p of opened) await p.browser.close().catch(() => {});
  process.exit(code);
}

async function main() {
  console.log(`[1] three browsers; the move happens ${MOVE_AT_S}s after the ring`);
  h.refuseIfAnotherRunIsLive();
  const L1 = await h.openParticipant('learnerFirstDevice', ROOM, 9741);
  opened.push(L1);
  const L2 = await h.openParticipant('learnerSecondDevice', ROOM, 9742);
  opened.push(L2);
  const C = await h.openParticipant('calltester', ROOM, 9743);
  opened.push(C);
  const LEARNER = L1.userId;
  // Every console line each browser prints, timestamped, for diagnosis.
  const fs = require('fs');
  for (const p of opened) {
    const file = h.cfg.shot(`console_${p.name}.log`);
    fs.writeFileSync(file, '');
    p.page.on('console', (m) => {
      try { fs.appendFileSync(file, `${new Date().toISOString()} ${m.text()}\n`); } catch (_) {}
    });
  }

  const before = await mx.liveMembershipDevices(L1.token, ROOM_ID, LEARNER);
  h.check(s, 'no learner device is in a call before the run', before.length === 0,
    `already in on ${before.join(', ')}`);
  if (before.length) { h.report(); await finish(2); }

  console.log('[2] the other person calls; device one answers');
  const markRing = await h.mark(C.token, ROOM_ID);
  const rang = await h.actUntil('place call',
    async () => { await h.ensureRoom(C, ROOM); await ui.clickControl(C.page, 'call').catch(() => {}); },
    async () => (await h.since(C.token, ROOM_ID, markRing)).some((e) => e.type === mx.RING && e.sender === C.userId),
    { tries: 4, gap: 4000 });
  h.check(s, 'the call rang', rang, 'no ring event');
  if (!rang) { h.report(); await finish(2); }
  const ringAt = Date.now();
  const ring = (await h.since(C.token, ROOM_ID, markRing)).find((e) => e.type === mx.RING && e.sender === C.userId);
  const callKey = ring?.content?.['m.relates_to']?.event_id;
  console.log(`   (call key ${callKey})`);

  let d1 = null;
  for (let i = 0; i < 15 && !d1; i++) {
    await ui.clickBanner(L1.page, 'answer').catch(() => {});
    await wait(2000);
    const devs = await mx.liveMembershipDevices(L1.token, ROOM_ID, LEARNER);
    if (devs.length === 1) d1 = devs[0];
  }
  h.check(s, 'device one answered', !!d1, 'no learner membership appeared');
  if (!d1) { h.report(); await finish(2); }
  console.log(`   (device one is ${d1})`);

  const waitMs = ringAt + MOVE_AT_S * 1000 - Date.now();
  console.log(`[3] talking on device one for ${Math.round(waitMs / 1000)}s more`);
  if (waitMs > 0) await wait(waitMs);

  console.log('[4] device two joins the call under way');
  let d2 = null;
  for (let i = 0; i < 8 && !d2; i++) {
    await h.ensureRoom(L2, ROOM);
    await ui.clickControl(L2.page, 'call').catch(() => {});
    for (let j = 0; j < 6 && !d2; j++) {
      await wait(2000);
      const devs = await mx.liveMembershipDevices(L1.token, ROOM_ID, LEARNER);
      d2 = devs.find((d) => d !== d1) || null;
    }
  }
  const joinedAt = Math.round((Date.now() - ringAt) / 1000);
  h.check(s, 'device two joined the call', !!d2, 'no second learner membership');
  if (!d2) { h.report(); await finish(2); }
  console.log(`   (device two is ${d2}, joined ${joinedAt}s after the ring)`);

  console.log('[5] device two: "Use this device"');
  // Every translation of each label: the app renders in the account's own
  // language, and the first literal the arb files yield need not be English.
  const useThisAll = new Set(labels.labelsFor('callDevicesUseThis'));
  const elsewhereAll = labels.labelsFor('callContinuingElsewhere');
  // Asked of the SCREEN, not of the membership state: one account's devices
  // share ONE membership state event, so the list it holds says nothing
  // reliable about which device is still in the call.
  let clicked = false;
  let moved = false;
  for (let i = 0; i < 20 && !moved; i++) {
    if (!clicked) {
      const onScreen = await ui.labels(L2.page).catch(() => []);
      const label = onScreen.find((n) => useThisAll.has(n));
      if (label) {
        const r = await ui.findRect(L2.page, label, { exact: true }).catch(() => null);
        if (r) {
          await L2.page.mouse.click(r.x, r.y);
          clicked = true;
          console.log(`   (clicked "${label}" on device two, ${Math.round((Date.now() - ringAt) / 1000)}s after the ring)`);
        }
      } else if (i === 3) {
        await L2.page.screenshot({ path: h.cfg.shot('move_device_two.png') }).catch(() => {});
        console.log(`   (no prompt yet on device two; it shows ${onScreen.length} labels)`);
      }
    }
    await wait(2000);
    if (clicked) {
      const one = await ui.labels(L1.page).catch(() => []);
      moved = elsewhereAll.some((t) => one.some((n) => n.includes(t)));
    }
  }
  h.check(s, 'device two was offered "Use this device" and it was pressed', clicked, 'no prompt seen');
  // And the CALL carried on: the other person is still in it. One account's
  // devices share one membership state event, so a sibling's leave that wrote
  // that list empty would read to the other person as a hangup.
  await wait(6000);
  const peerStill = await mx.liveMembershipDevices(C.token, ROOM_ID, C.userId);
  h.check(s, 'the call carried on after the move (the other person is still in it)',
    peerStill.length === 1, `the other person's live devices: ${peerStill.length}`);
  if (!moved) console.log('   (device one\'s "continuing on your other device" note was not caught on screen)');

  console.log(`[6] talking on device two for ${TALK_AFTER_S}s, then hanging up`);
  await wait(TALK_AFTER_S * 1000);
  await h.actUntil('hang up',
    async () => { await ui.clickPanel(L2.page, 'hangup').catch(() => {}); },
    async () => (await mx.liveMembershipDevices(L1.token, ROOM_ID, LEARNER)).length === 0,
    { tries: 5, gap: 3000 });

  console.log(`[7] waiting up to ${SETTLE_S}s for the halves and the full-call recording`);
  let audio = [];
  let merged = [];
  let transcripts = [];
  const deadline = Date.now() + SETTLE_S * 1000;
  while (Date.now() < deadline) {
    audio = await relations(C.token, callKey, AUDIO);
    merged = await relations(C.token, callKey, MERGED);
    transcripts = await relations(C.token, callKey, TRANSCRIPT);
    const mine = audio.filter((e) => e.sender === LEARNER);
    const mineT = transcripts.filter((e) => e.sender === LEARNER && !e.content?.spoken_by);
    if (mine.length >= 2 && mineT.length >= 2 && merged.length >= 1) break;
    await wait(10000);
  }
  const mineAudio = audio.filter((e) => e.sender === LEARNER);
  const peerAudio = audio.filter((e) => e.sender !== LEARNER);
  const mineHalves = transcripts.filter((e) => e.sender === LEARNER && !e.content?.spoken_by);
  console.log(`   audio: ${audio.map((e) => `${e.sender === LEARNER ? 'learner' : 'peer'}/${e.content?.device_id} from=${e.content?.continued_from || '-'} to=${e.content?.handed_over_to || '-'}`).join('; ') || 'none'}`);
  console.log(`   transcript halves: ${transcripts.map((e) => `${e.sender === LEARNER ? 'learner' : 'peer'}/${e.content?.device_id}${e.content?.spoken_by ? ' (for ' + e.content.spoken_by + ')' : ''}`).join('; ') || 'none'}`);
  console.log(`   merged: ${merged.map((e) => `${(e.content?.source_event_ids || []).length} sources complete=${e.content?.complete}`).join('; ') || 'none'}`);

  const a1 = mineAudio.find((e) => e.content?.device_id === d1);
  const a2 = mineAudio.find((e) => e.content?.device_id === d2);
  h.check(s, 'device one (moved FROM) posted its recording', !!a1, 'no recording from device one');
  h.check(s, 'device two (moved TO) posted its recording', !!a2, 'no recording from device two');
  h.check(s, 'device one names device two as where the call went',
    a1?.content?.handed_over_to === d2, `handed_over_to=${a1?.content?.handed_over_to}`);
  h.check(s, 'device two either names device one or carries no link',
    !a2 || a2.content?.continued_from === d1 || a2.content?.continued_from === undefined,
    `continued_from=${a2?.content?.continued_from}`);
  h.check(s, 'the other person posted their recording', peerAudio.length === 1, `${peerAudio.length}`);

  const t1 = mineHalves.find((e) => e.content?.device_id === d1);
  const t2 = mineHalves.find((e) => e.content?.device_id === d2);
  h.check(s, 'device one posted a transcript half', !!t1, 'none');
  h.check(s, 'device two posted a transcript half', !!t2, 'none');

  const allIds = new Set(audio.map((e) => e.event_id));
  const whole = merged.filter((m) => {
    const ids = new Set(m.content?.source_event_ids || []);
    return ids.size === allIds.size && [...allIds].every((id) => ids.has(id)) && m.content?.complete === true;
  });
  h.check(s, 'one complete full-call recording names every recording of the call',
    whole.length === 1, `${merged.length} merged, ${whole.length} covering all ${allIds.size}`);

  const learnerText = mineHalves.map(spoken).join(' ');
  const pre = hits(learnerText, BEFORE_WORDS);
  const post = hits(learnerText, AFTER_WORDS);
  console.log(`   learner words before the move: ${pre.join(', ') || 'none'}; after: ${post.join(', ') || 'none'}`);
  h.check(s, "the learner's words from BEFORE the move are in the transcript", pre.length >= 2, `${pre.length} found`);
  h.check(s, "the learner's words from AFTER the move are in the transcript", post.length >= 2, `${post.length} found`);

  for (const p of opened) {
    h.check(s, `${p.name} had no unhandled errors`, p.errors.length === 0, p.errors.slice(0, 2).join(' | '));
  }
  const unproven = h.report();
  await finish(unproven ? 1 : 0);
}

main().catch(async (e) => {
  console.error(e);
  await finish(3);
});
