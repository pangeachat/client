// The rest of the app, with the call work in it.
//
// The calling branch pins a fork of the Matrix SDK, and the fork changes the
// VoIP lifecycle. Nothing else should notice -- but "should" is not evidence,
// and the thing everybody uses every day is an ordinary message. This sends
// one from the UI and proves it arrived on both the server and the other
// person's screen.
const h = require('./harness');
const cfg = require('./config');
const { ui, mx, wait } = h;
h.refuseIfAnotherRunIsLive();

const ROOM = cfg.room;
const ROOM_ID = cfg.roomId;

(async () => {
  const A = await h.openParticipant('learner', ROOM, 9791);
  const B = await h.openParticipant('calltester', ROOM, 9792);
  const mark = await h.mark(A.token, ROOM_ID);
  const text = `sanity ${Date.now()}`;

  console.log('[1] a message is sent to the room');
  // Sent over the API rather than through the composer: what this is here to
  // prove is that the SDK the calling branch pins still SYNCS and RENDERS an
  // ordinary message. The composer's own path is covered by the quick-reply
  // scenario, which sends a real m.room.message from the UI.
  await h.ensureRoom(A, ROOM);
  await mx.api(
    `/_matrix/client/v3/rooms/${encodeURIComponent(ROOM_ID)}/send/`
    + `m.room.message/${Date.now()}`,
    { token: A.token, method: 'PUT', body: { msgtype: 'm.text', body: text } },
  );
  const landed = await h.actUntil(
    'server has it',
    async () => {},
    async () => {
      const events = await h.since(A.token, ROOM_ID, mark);
      return events.some(
        (e) => e.type === 'm.room.message' && e.content?.body === text,
      );
    },
    { tries: 5, gap: 2000 },
  );
  h.check('messaging', 'the message reaches the room', landed,
    'no m.room.message with that body arrived');

  console.log('[2] the other person sees it');
  await h.ensureRoom(B, ROOM);
  let seen = false;
  for (let i = 0; i < 10 && !seen; i++) {
    const body = await B.page.evaluate(() => document.body.innerText || '');
    seen = body.includes(text);
    if (!seen) await wait(2000);
  }
  h.check('messaging', 'the message renders for the other person', seen,
    'the text never appeared on the receiving side');

  console.log('[3] neither side logged an unhandled error');
  h.check('messaging', 'learner had no unhandled errors', A.errors.length === 0,
    JSON.stringify(A.errors).slice(0, 300));
  h.check('messaging', 'calltester had no unhandled errors', B.errors.length === 0,
    JSON.stringify(B.errors).slice(0, 300));

  await A.browser.close();
  await B.browser.close();
  process.exit(h.report() === 0 ? 0 : 1);
})().catch((e) => { console.error('FAILED', e.message); process.exit(1); });
