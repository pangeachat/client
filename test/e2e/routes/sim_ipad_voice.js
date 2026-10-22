// SIMULATOR leg of the route suite: a browser peer (calltester) calls an
// account signed in on the iOS SIMULATOR (an iPad by default), which answers
// by hand -- the script waits for its call membership and says so. Asserted
// from the server exactly as the browser routes are, plus the simulator's
// transcript screen read by OCR off `xcrun simctl io screenshot`.
//
//   SIM_UDID=<udid> SIM_ACCOUNT=routes_fr SIM_ROOM=fr_calltester SIM_WAV=<fixture> \
//   SIM_LANG=fr node test/e2e/routes/sim_ipad_voice.js
//
// AUDIO: the simulator records the Mac's default microphone; nothing can be
// injected into it without a virtual audio device. This plays SIM_WAV out of
// the Mac's speakers (afplay) so the Mac microphone hears it: a real acoustic
// path, which also hears the peer's voice coming out of the same speakers.
// Words checks on the simulator speaker's half are therefore about whether
// the pipeline transcribed SOMETHING in the right language, not attribution.
const fs = require('fs');
const path = require('path');
const { spawn, spawnSync } = require('child_process');
const R = require('./lib');

const { h, mx, wait, cfg } = R;
const s = process.env.SIM_ROUTE || 'sim_ipad_voice';
const opened = [];

function simShot(udid, tag) {
  const f = path.join(cfg.ensureDir(cfg.shotsDir), `sim-${tag}.png`);
  spawnSync('xcrun', ['simctl', 'io', udid, 'screenshot', f]);
  const r = spawnSync('tesseract', [f, '-', '--psm', '11'], { encoding: 'utf8' });
  const text = r.status === 0 ? String(r.stdout || '') : null;
  if (text != null) R.save(`sim-${tag}.txt`, text);
  return text;
}

async function main() {
  const udid = process.env.SIM_UDID;
  if (!udid) throw new Error('set SIM_UDID (xcrun simctl list devices booted)');
  const simName = process.env.SIM_ACCOUNT || 'routes_fr';
  const roomKey = process.env.SIM_ROOM || 'fr_calltester';
  const lang = process.env.SIM_LANG || 'fr';
  const wav = process.env.SIM_WAV || R.fixture('fr_mix');
  const talkS = Number(process.env.SIM_TALK_S || 45);
  const words = lang === 'fr' ? R.WORDS.frL2 : lang === 'es' ? R.WORDS.esL2 : R.WORDS.learner;
  R.refuseIfNotLocal();
  h.refuseIfAnotherRunIsLive();
  await R.refuseIfLearning(simName, lang);
  await R.ensureSubscriptions({ [simName]: true, calltester: true });
  const roomLp = R.rooms()[roomKey];
  const roomId = R.fullRoomId(roomLp);
  await R.waitNoLiveCall([simName, 'calltester'], roomId);

  const simAcct = cfg.accounts[simName];
  const S = await mx.login(simAcct.user, simAcct.pass);
  const P = await R.openP('calltester', roomLp, 9781, { wav: R.fixture('peer') });
  opened.push(P);

  const call = await R.placeAndAnswer(s, P, null, roomId, { answer: false });
  if (!call) return R.finish(s, opened);
  console.log('>>> ANSWER THE CALL ON THE SIMULATOR NOW');
  let joined = false;
  for (let i = 0; i < 25 && !joined; i++) {
    await wait(2000);
    joined = await mx.hasMembership(S.token, roomId, S.userId);
  }
  h.check(s, `the simulator (${simName}) answered (membership published)`, joined, 'no membership from the simulator account');
  if (!joined) { await R.hangUp(s, P, roomId); return R.finish(s, opened); }
  const answeredAt = Date.now();
  simShot(udid, 'in-call');

  console.log(`   (playing ${path.basename(wav)} out of the Mac speakers for ${talkS}s)`);
  const player = spawn('afplay', ['-t', String(talkS), wav], { stdio: 'ignore' });
  await wait(talkS * 1000 + 2000);
  player.kill();
  const callSeconds = Math.round((Date.now() - answeredAt) / 1000);
  await R.hangUp(s, P, roomId);
  for (let i = 0; i < 10 && await mx.hasMembership(S.token, roomId, S.userId); i++) await wait(3000);
  h.check(s, 'the simulator left the call after the peer hung up', !(await mx.hasMembership(S.token, roomId, S.userId)), 'simulator membership still live');

  const got = await R.collect(P.token, roomId, call.callKey, { halves: 2, audio: 2, merged: 1, settleS: 300 });
  R.save('events.json', { callKey: call.callKey, callSeconds, transcripts: got.transcripts.map(R.summarise), audio: got.audio.map(R.summarise), merged: got.merged.map(R.summarise) });
  const simHalves = got.transcripts.filter((e) => (e.content?.spoken_by || e.sender) === S.userId);
  const simText = simHalves.map(R.spoken).join(' ');
  const simWords = R.hitsOf(simText, words);
  h.check(s, `the simulator speaker's half was transcribed (any ${lang} fixture words, through the Mac speakers)`, simWords.length >= 1,
    `${simHalves.length} half/halves; words: ${[...R.wordSet(simText)].slice(0, 20).join(' ') || '(none)'}`);
  h.check(s, 'the simulator saved its recording (pangea.call_audio)', got.audio.some((e) => e.sender === S.userId),
    `call_audio from ${[...new Set(got.audio.map((e) => e.sender))].join(', ') || 'nobody'}`);
  h.check(s, 'the browser peer saved its recording', got.audio.some((e) => e.sender === P.userId), 'none from the peer');
  const ids = new Set(got.audio.map((e) => e.event_id));
  const whole = got.merged.filter((m) => m.content?.complete === true && (m.content?.source_event_ids || []).length === ids.size);
  h.check(s, 'one complete full-call recording', whole.length === 1, `${got.merged.length} merged, ${whole.length} complete`);
  await R.assertPlays(s, P.token, whole[0], callSeconds);

  console.log('>>> OPEN THE NEWEST CALL TRANSCRIPT ON THE SIMULATOR (waiting 60s)');
  await wait(60000);
  const t = simShot(udid, 'transcript');
  if (t == null) h.skipped(s, 'the simulator transcript screen offers the full-call recording', 'simulator screenshot/OCR failed');
  else {
    h.check(s, 'the simulator transcript screen offers the full-call recording', !R.ocrHas(t, 'No recording of the full call') && R.ocrHas(t, 'Full call'), R.ocrHas(t, 'No recording of the full call') ? '"No recording of the full call." shown' : 'no "Full call" read');
    h.check(s, 'the simulator transcript does not say the speaker said nothing', !R.ocrHas(t, 'did not say anything'), '"did not say anything" shown');
  }
  await mx.logout(S.token).catch(() => {});
  return R.finish(s, opened, { udid, simName, callKey: call.callKey, callSeconds });
}

main().catch(R.fatal(s, opened));
