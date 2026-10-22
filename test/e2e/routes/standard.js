// The standard route: one 1:1 call between two accounts, with a subscription
// pair, a network condition, an optional app kill during upload, and optional
// language / acoustic checks. Every #3350 pass criterion is asked here; the
// route files only say which combination they are.
const R = require('./lib');

const { h, ui, mx, wait, cfg } = R;

async function runStandardCall(def) {
  const s = def.id;
  const opened = [];
  const closed = [];
  const roomLp = R.rooms()[def.room || 'learner_calltester'];
  const roomId = R.fullRoomId(roomLp);
  const A0 = def.A || 'learner';
  const B0 = def.B || 'calltester';
  const sub = def.sub; // { A: bool, B: bool }
  const anySubscribed = sub.A || sub.B;
  const talkS = def.talkS || 50;
  const net = def.network || { mode: 'good' };

  try {
    console.log(`[${s}] ${def.title}`);
    R.refuseIfNotLocal();
    h.refuseIfAnotherRunIsLive();
    await R.refuseIfLearning(A0, def.langA || 'en');
    await R.refuseIfLearning(B0, def.langB || 'en');
    await R.ensureSubscriptions({ [A0]: !!sub.A, [B0]: !!sub.B });
    await R.waitNoLiveCall([A0, B0], roomId);

    const A = await R.openP(A0, roomLp, 9751, { wav: def.wavA });
    opened.push(A);
    const B = await R.openP(B0, roomLp, 9752, { wav: def.wavB });
    opened.push(B);
    const netTarget = net.who === 'A' ? A : B;
    if (net.mode === 'throttled') { await R.setNetwork(A, 'throttled'); await R.setNetwork(B, 'throttled'); }

    const call = await R.placeAndAnswer(s, A, B, roomId, { video: !!def.video });
    if (!call) return R.finish(s, opened, { def, closed });
    console.log(`   (call key ${call.callKey})`);

    // The consent notice (before the recording is read back).
    await wait(5000);
    const during = await R.dumpLabels(A, 'in-call');
    const panelText = (await A.page.evaluate(() => document.body.innerText || '').catch(() => '')).replace(/\s+/g, ' ');
    const notice = R.L('callTranscriptSharedNotice').map((t) => t.split('.')[0].trim()).filter((t) => t.length > 12);
    h.check(s, 'the recording notice is shown during the call', notice.some((t) => panelText.includes(t) || during.some((l) => l.includes(t))),
      'no "This call is transcribed and saved" notice on the caller');

    if (net.mode === 'dropMid') {
      await wait((def.dropAtS || 25) * 1000);
      await R.setNetwork(netTarget, 'offline');
      await wait((def.dropForS || 20) * 1000);
      await R.dumpLabels(netTarget, 'offline');
      await R.setNetwork(netTarget, 'good');
      const remaining = talkS - (def.dropAtS || 25) - (def.dropForS || 20);
      await wait(Math.max(remaining, 15) * 1000);
      const still = await mx.hasMembership(A.token, roomId, A.userId) && await mx.hasMembership(B.token, roomId, B.userId);
      h.check(s, 'the call survived the mid-call drop (both still in it)', still, 'a membership went away after the drop');
    } else {
      await wait(talkS * 1000);
    }

    if (net.mode === 'dropEnd') {
      await R.setNetwork(netTarget, 'offline');
      await wait(2000);
    }
    const callSeconds = Math.round((Date.now() - call.answeredAt) / 1000);
    await R.hangUp(s, A, roomId);
    const endedAt = Date.now();

    let Bnow = B;
    if (def.killDuringUpload && netTarget !== B) throw new Error('killDuringUpload is written for the callee (network.who B)');
    if (def.killDuringUpload) {
      // The app is killed while its recording is still to be uploaded, then
      // reopened with the network back.
      await wait(4000);
      console.log(`   (SIGKILL ${netTarget.name} during upload)`);
      await R.saveParticipant(netTarget);
      await h.kill(netTarget);
      opened.splice(opened.indexOf(netTarget), 1);
      closed.push(netTarget);
      await wait(def.killForS ? def.killForS * 1000 : 10000);
      const re = await R.openP(netTarget.name, roomLp, netTarget.port, { wav: netTarget === A ? def.wavA : def.wavB });
      re.name = netTarget.name;
      opened.push(re);
      if (netTarget === B) Bnow = re;
      console.log(`   (${re.name} relaunched; network good)`);
    } else if (net.mode === 'dropEnd') {
      await wait(15000);
      await R.setNetwork(netTarget, 'good');
    }
    if (net.mode === 'throttled') { /* stays throttled through the upload on purpose */ }

    // Loading state, asked of a subscribed reader right away.
    const reader = sub.A ? A : (sub.B ? Bnow : null);
    if (reader) await R.watchLoading(s, reader);

    console.log('   (waiting for the halves, the recordings and the full-call recording)');
    const got = await R.collect(A.token, roomId, call.callKey, {
      halves: anySubscribed ? (sub.A && sub.B ? 2 : 3) : 2, audio: 2, merged: 1, settleS: def.settleS || 300,
    });
    if (net.mode === 'throttled') { await R.setNetwork(A, 'good').catch(() => {}); await R.setNetwork(Bnow, 'good').catch(() => {}); }
    R.save('events.json', {
      callKey: call.callKey, ring: call.ring?.event_id, callSeconds,
      transcripts: got.transcripts.map(R.summarise), audio: got.audio.map(R.summarise),
      merged: got.merged.map(R.summarise), clock: got.clock.map(R.summarise),
    });
    console.log(`   halves: ${got.transcripts.length}  audio: ${got.audio.length}  merged: ${got.merged.length}`);

    const speakers = [
      { p: A, words: def.wordsA || R.WORDS.learner },
      { p: Bnow, words: def.wordsB || R.WORDS.peer },
    ];
    const merged = R.assertTranscriptCriteria(s, got, speakers, { anySubscribed, call });
    await R.assertPlays(s, A.token, merged, callSeconds);

    if (sub.A !== sub.B) {
      const unsub = sub.A ? Bnow : A;
      const subd = sub.A ? A : Bnow;
      const produced = got.transcripts.find((e) => e.sender === subd.userId && e.content?.spoken_by === unsub.userId);
      h.check(s, "the subscriber's device produced the unsubscribed person's half (spoken_by)", !!produced,
        'no half from the subscriber with spoken_by = the unsubscribed person');
    }

    if (def.l1Words) {
      const mine = got.transcripts.filter((e) => (e.content?.spoken_by || e.sender) === A.userId).map(R.spoken).join(' ');
      const l1 = R.hitsOf(mine, def.l1Words);
      h.check(s, `${A.name}'s L1 (English) speech comes back as English text (#3351)`, l1.length >= 2,
        `${l1.length} of ${def.l1Words.join('/')} found; the L1 sentences were dropped or translated. Got: ${[...R.wordSet(mine)].slice(0, 20).join(' ')}`);
    }
    if (def.checkRepetition) {
      for (const e of got.transcripts) {
        const rep = R.repetition(R.spoken(e));
        h.check(s, `no runaway repetition in ${e.content?.spoken_by || e.sender}'s half (#3356)`, !rep, `repeated ${rep}`);
      }
    }

    // What each screen says once everything landed.
    const sA = { name: A.name, ...(await R.readTranscriptScreen(A)) };
    const sB = { name: Bnow.name, ...(await R.readTranscriptScreen(Bnow)) };
    h.check(s, 'both people can open the transcript from the call card', sA.opened && sB.opened, `A opened ${sA.opened}, B opened ${sB.opened}`);
    R.assertScreens(s, [sA, sB], {
      subscribed: [sub.A ? sA : null, sub.B ? sB : null].filter(Boolean),
      unsubscribed: [sub.A ? null : sA, sub.B ? null : sB].filter(Boolean),
      anySubscribed,
    });

    if (anySubscribed) {
      const anchors = [call.ring?.event_id, call.callKey];
      const cards = (await R.eventsSince(A.token, roomId, call.mark, [mx.CALL])).map((e) => e.event_id);
      const sp = [sub.A ? A : null, sub.B ? Bnow : null].filter(Boolean);
      await R.checkCreditOnce(s, sp, [...anchors, ...cards].filter(Boolean), call.ringAt - 60000);
    }
    // The subscriptions the route was judged under must still hold: an app
    // that claimed a trial mid-route would make "unsubscribed" a lie.
    await R.confirmSubscriptions(s, { [A0]: !!sub.A, [B0]: !!sub.B });
    const cards = mx.cardsIn(await R.eventsSince(A.token, roomId, call.mark, [mx.CALL]), A.userId);
    h.check(s, 'the call left exactly one card, answered', cards.length === 1 && cards[0].answered, JSON.stringify(cards));
    return R.finish(s, opened, { def, callKey: call.callKey, callSeconds, endedAt, closed });
  } catch (e) {
    return R.fatal(s, opened)(e);
  }
}

module.exports = { runStandardCall };
