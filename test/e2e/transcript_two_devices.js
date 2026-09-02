// TWO DEVICES OF ONE ACCOUNT IN ONE CALL.
//
// `transcript.js` proves what two PEOPLE end up with. This proves what one
// person ends up with when they are signed in twice -- the case a transcript
// half used to be destroyed by, and the one case a hand-driven test cannot
// reach at all, because it takes three browsers and two of them have to be the
// same account.
//
// WHAT USED TO HAPPEN. A half was keyed by the SENDER. Two of a learner's
// devices in one call wrote two halves that nothing could tell apart, so the
// reader kept ONE of them and presented it -- with its own accounting, which
// said it was complete -- as the whole of what that person said. The other
// device's speech was destroyed silently. That is worse than a refused send:
// a refusal is visible.
//
// The fix keys a half by DEVICE and MERGES an account's halves, and the unit
// tests for it pass. That is not the same claim as this file's. A unit test
// hands `assembleTranscript` two candidates it built itself; nothing before
// this ran a second real client, on a real homeserver, and asked whether two
// halves are what actually reaches the room.
//
// FOUR THINGS, and each is asked of the SERVER, of the WIRE, or of the SCREEN,
// never of the click that was supposed to cause it.
//
//   1. BOTH HALVES SURVIVE. Two `pangea.call_transcript` events from the ONE
//      account, carrying DIFFERENT device ids -- and those two ids are the two
//      devices the server itself says were in the call.
//   2. THE TRANSACTION IDS DIFFER, AND THE PRODUCT'S OWN IDS ARE THE ONES
//      COMPARED. Matrix never sends a transaction id back down, so this is
//      taken from the OUTGOING request each browser made -- the PUT path the
//      app itself built -- and only then checked against the id the app's
//      formula derives from the event that arrived. A recomputation on its own
//      would prove the events carry enough to derive two ids and nothing about
//      what was sent, which is a weaker sentence than this file needs.
//   3. THE READER MERGED THEM. Read off the app's own read-time log, which
//      states how many devices a half was assembled from -- the one place the
//      count is visible, and the only proof that survives the ordinary case
//      where `CaptureElection` left one of the two halves empty. A drawn-turn
//      count cannot tell a merge from a reader that dropped an empty half;
//      this can, so it is the check the merge rests on rather than the screen.
//   4. NOTHING IS LOST. Every word any half carries is on the screen
//      afterwards, and nobody who spoke is reported as having said nothing.
//
// AND EVERY ONE OF THEM FAILS WHEN IT CANNOT BE ASKED. A check that reports
// SKIP, and a wait that runs out and carries on, are both ways of not knowing,
// and not knowing is not success: the exit code counts an inconclusive check
// exactly as it counts a failed one (see the end of [main]). This file exited 0
// once while its central claim -- that the reader merges -- had proved nothing
// at all, because the only check that spoke to it skipped.
//
// WHAT THE PRODUCT DOES THAT SHAPES THIS FILE.
//
// `CaptureElection` means the two devices do NOT normally both record: they
// rank themselves by device id and exactly one of them holds the recording,
// so the ordinary outcome is one half with speech and one half with none. That
// is not a weaker case than two speaking halves -- it is the SHARPER one. The
// half that gets dropped when a reader keeps only one is as likely to be the
// full one as the empty one, and dropping it turns a learner who talked for a
// minute into a learner the screen says was silent.
//
// Which device wins is decided by a device id nobody chooses -- so this file
// works out which one that is and hangs THAT one up, rather than tossing for
// it. `CaptureElection` is a total order, capability first and device id
// second, and this stack cannot publish capability at all, so the recorder is
// simply the lower of the two ids the server saw join. Pairing that id with a
// BROWSER is the only part that needs machinery: see [deviceOfPage].
//
// When the pairing cannot be made the run falls back to the CALL_HANDOVER_DEVICE
// knob and says so -- and then the outcome is checked rather than assumed. A run
// that ends with one empty half FAILS on `BOTH of the learner devices
// transcribed`, because a screen drawn from one empty half and one full one is
// a screen a reader that dropped the empty one draws too.
//
// AND GETTING TWO DEVICES INTO ONE CALL AT ALL IS ITS OWN FINDING. The ring
// flow will not do it: `answeredOnAnotherDevice` dismisses the second device's
// prompt the moment the first one's membership lands, deliberately, so once one
// device has answered the other is offered no way in. The only route left is
// the one the product's own code names -- the convergence race, both devices
// answering in the same instant -- so that is what step [2] drives, and it
// retries the RACE rather than the click.
const h = require('./harness');
const { ui, mx, wait } = h;
const labels = require('./labels');

const { room: ROOM, roomId: ROOM_ID, shot, accounts } = h.cfg;

/// The transcript relation, as the writer sends it.
const TRANSCRIPT = 'pangea.call_transcript';

/// The call membership state event, one per account, listing that account's
/// devices in the call.
const MEMBER = 'com.famedly.call.member';

/// The transaction id the app's formula DERIVES from an event that arrived.
///
/// A COPY of `CallTranscriptContent.txnId`, kept in the same shape as the Dart,
/// empty segment and all, so a change there that this file did not follow shows
/// up as a check that stops meaning what it says.
///
/// WHAT IT PROVES ON ITS OWN, WHICH IS LESS THAN IT LOOKS. Matrix never sends a
/// transaction id back down, so this cannot witness what the product sent: it
/// says only that the two events that ARRIVED carry enough between them to
/// derive two different ids. An app that had regressed to the old
/// `(call key, sender)` formula, on a homeserver that happened to accept both
/// devices' requests, would land two events this recomputes two distinct ids
/// from -- and the check would pass while the product was doing the one thing
/// this file exists to catch. The check named after this function says exactly
/// that much and no more; [transcriptSendsOf] is what witnesses the real ids.
///
/// `usableDeviceId` in the app refuses an empty id and anything past 255
/// characters; absent, empty and over-long all key ALIKE, which is the whole
/// point -- so they all reduce to the empty segment here too.
const txnIdOf = (ev) => {
  const raw = ev?.content?.device_id;
  const device =
    typeof raw === 'string' && raw.length > 0 && raw.length <= 255 ? raw : '';
  return `pangea.call_transcript:${ev?.content?.call_key}:${ev?.sender}:${device}`;
};

/// Watches what a page actually PUTS at the homeserver.
///
/// THE ONE OBSERVABLE THAT WITNESSES A TRANSACTION ID. It travels in the PATH
/// of the send -- `PUT /_matrix/client/v3/rooms/{room}/send/{type}/{txnId}` --
/// and nowhere else: the server does not echo it back to anyone but the sending
/// device's own sync, and the harness's token is a different device. So the
/// only place the id the PRODUCT used is visible is the request the product
/// made, and this reads it there.
///
/// It also lifts the session's bearer token, which is the only way to ask which
/// Matrix DEVICE a browser is. Kept in memory for the length of the run, never
/// logged and never written to any of the files this scenario keeps; these are
/// a laptop's own Synapse and the fixture accounts the whole folder is built
/// on.
///
/// Installed as a function so `evaluateOnNewDocument` can run it before any of
/// the app's own script does, and idempotent so a navigation cannot wrap the
/// wrapper. Both transports are covered: `package:http`'s browser client
/// compiles to `globalThis.fetch(url, init)`, and anything left on
/// XMLHttpRequest is caught beside it. Neither wrapper reads a body, so no
/// stream is consumed and nothing about the request changes.
function installSendWatch() {
  if (window.__pangeaSendWatch) return;
  window.__pangeaSendWatch = true;
  const SENDS = '__pangea_sends';
  const AUTH = '__pangea_auth';
  // ONLY a Matrix client-server request's token, and the scope is the whole
  // point. The app also talks to the choreographer, with a bearer of its own,
  // and a watcher that took whichever Authorization went past last would hand
  // the harness that one -- which resolves against the homeserver as
  // M_UNKNOWN_TOKEN, and reports as a browser whose device could not be
  // identified. Measured: the probe that built this saw exactly that.
  const noteAuth = (url, value) => {
    if (String(url || '').indexOf('/_matrix/client/') === -1) return;
    const v = String(value || '').replace(/^Bearer\s+/i, '');
    if (!v) return;
    try {
      window.sessionStorage.setItem(AUTH, v);
    } catch (_) {
      // Storage denied is a harness fact, and one the reader below reports as
      // a token it could not get -- never as a device that was not there.
    }
  };
  const noteSend = (url) => {
    const u = String(url || '');
    const m = u.match(/\/_matrix\/client\/[^/]+\/rooms\/([^/?#]+)\/send\/([^/?#]+)\/([^/?#]+)/);
    if (!m) return;
    try {
      const prev = JSON.parse(window.sessionStorage.getItem(SENDS) || '[]');
      prev.push({
        room: decodeURIComponent(m[1]),
        type: decodeURIComponent(m[2]),
        txnId: decodeURIComponent(m[3]),
        at: Date.now(),
      });
      // A ceiling, because a long call sends a great many events and this is a
      // diagnostic rather than a ledger. Transcript halves are written LAST, so
      // the tail is the end of the file that matters.
      window.sessionStorage.setItem(SENDS, JSON.stringify(prev.slice(-400)));
    } catch (_) {}
  };
  const headerOf = (headers, name) => {
    try {
      if (!headers) return '';
      if (typeof headers.get === 'function') return headers.get(name) || '';
      if (Array.isArray(headers)) {
        const row = headers.find((h) => String(h[0]).toLowerCase() === name);
        return row ? String(row[1]) : '';
      }
      for (const k of Object.keys(headers)) {
        if (k.toLowerCase() === name) return String(headers[k]);
      }
    } catch (_) {}
    return '';
  };
  const realFetch = window.fetch;
  if (typeof realFetch === 'function') {
    window.fetch = function (input, init) {
      try {
        const isRequest = input && typeof input === 'object' && 'url' in input;
        const url = isRequest ? input.url : input;
        noteSend(url);
        noteAuth(url, headerOf(
          (init && init.headers) || (isRequest ? input.headers : null),
          'authorization',
        ));
      } catch (_) {
        // A watcher may never be the reason a request does not go out.
      }
      return realFetch.apply(this, arguments);
    };
  }
  const XHR = window.XMLHttpRequest;
  if (XHR && XHR.prototype) {
    const realOpen = XHR.prototype.open;
    const realHeader = XHR.prototype.setRequestHeader;
    const realSend = XHR.prototype.send;
    XHR.prototype.open = function (method, url) {
      try { this.__pangeaUrl = url; } catch (_) {}
      return realOpen.apply(this, arguments);
    };
    XHR.prototype.setRequestHeader = function (name, value) {
      try {
        if (String(name).toLowerCase() === 'authorization') {
          noteAuth(this.__pangeaUrl, value);
        }
      } catch (_) {}
      return realHeader.apply(this, arguments);
    };
    XHR.prototype.send = function () {
      try { noteSend(this.__pangeaUrl); } catch (_) {}
      return realSend.apply(this, arguments);
    };
  }
}

/// Installs the watcher on a page that has not loaded anything yet.
async function watchSends(page) {
  await page.evaluateOnNewDocument(installSendWatch);
}

/// What the page has sent, and under which token, as it recorded it.
///
/// `sessionStorage` rather than a variable on `window`, so a navigation -- and
/// this scenario navigates between the call and the read -- does not throw the
/// record away.
///
/// THROWS rather than answering with an empty list. "The page sent no transcript
/// half" and "the harness could not read the page" are opposite findings, and
/// the second dressed as the first is how a check comes to fail for a reason
/// nobody can act on.
async function sentBy(page) {
  const raw = await page.evaluate(() => {
    try {
      return window.sessionStorage.getItem('__pangea_sends') || '[]';
    } catch (e) {
      return `!${e && e.message}`;
    }
  });
  if (typeof raw === 'string' && raw.startsWith('!')) {
    throw new Error(`the page would not give up its send log: ${raw.slice(1)}`);
  }
  return JSON.parse(raw);
}

/// The transcript sends among them, newest last.
const transcriptSendsOf = (sends) =>
  (Array.isArray(sends) ? sends : []).filter((r) => r && r.type === TRANSCRIPT);

/// Which Matrix DEVICE a browser is.
///
/// Asked of the homeserver with the browser's OWN token, because nothing else
/// can answer it: the app keeps no device id anywhere a page can read, the
/// harness's `mx.login` is a different device, and `/devices` cannot tell two
/// Chrome profiles on one laptop apart. Without it, which of the two devices
/// holds the recording -- and therefore which one leaving puts speech in both
/// halves -- is a coin toss, and the run's central case is reached half the
/// time.
///
/// Null when the token has not been seen yet; the caller waits and asks again.
async function deviceOfPage(page) {
  const token = await page.evaluate(() => {
    try {
      return window.sessionStorage.getItem('__pangea_auth') || '';
    } catch (_) {
      return '';
    }
  });
  if (!token) return null;
  return (await mx.whoami(token)).deviceId;
}

/// The words in a half, flattened.
function spoken(ev) {
  const segs = ev?.content?.segments;
  if (!Array.isArray(segs)) return '';
  return segs.map((s) => (s && typeof s.text === 'string' ? s.text : '')).join(' ');
}

/// Words of four letters or more, lowercased. A SET, for the reason
/// `transcript.js` gives: the provider decides its own punctuation and casing.
function words(text) {
  return new Set(
    text
      .toLowerCase()
      .split(/[^\p{L}\p{N}]+/u)
      .filter((w) => w.length >= 4),
  );
}

/// A distinctive word from each fixture.
///
/// THREE fixtures, because there are three microphones: the learner's two
/// devices and the other person's. The first two sets are what makes this file
/// able to say which of the learner's DEVICES a word came from -- and without
/// that, a reader that merged both halves and a reader that kept one are the
/// same screen.
///
/// EIGHT words a side rather than four, because the device that records second
/// only ever holds part of the call: its fixture repeats the same eight
/// sentences three times over, so whichever stretch it held carries some of
/// these. One is enough.
///
/// They move with the wavs. `config.js` says where those come from and the
/// README says how to make them; replace a fixture and this list moves with it,
/// or a run passes on a transcript of different audio.
const DEVICE_ONE_SAYS = [
  'compass', 'orchard', 'trumpet', 'glacier',
  'pelican', 'saffron', 'marble', 'thunder',
];
const DEVICE_TWO_SAYS = [
  'lantern', 'bicycle', 'harbor', 'november',
  'cinnamon', 'walnut', 'ferry', 'meadow',
];
const PEER_SAYS = ['course', 'orange', 'quarter', 'gardens'];

/// How long the survivor holds the call by itself after the handover.
///
/// Named because a check below quotes it: "captured nothing in the forty
/// seconds it held the call alone" is only a finding next to the number.
const HANDOVER_TAIL_MS = 40000;

/// The language every fixture is in. See `transcript.js`: speech-to-text is
/// asked for the SPEAKER'S OWN target language, so an account learning
/// something else has this English audio come back EMPTY rather than wrong --
/// and an empty half is exactly what this file is trying to tell a real merge
/// failure apart from.
const FIXTURE_LANG = 'en';

/// Refuses a run whose fixtures the accounts cannot be understood in.
///
/// Asked over its own API logins, BEFORE the browsers, on the same terms
/// `transcript.js` asks it: the alternative is three browsers and a two-minute
/// call to arrive at a conclusion only the account's settings could give.
async function refuseIfNotLearning(names) {
  for (const name of names) {
    const a = accounts[name];
    const { token, userId } = await mx.login(a.user, a.pass);
    let code;
    try {
      code = await mx.targetLanguage(token, userId);
    } finally {
      // A session taken for one question is a Matrix DEVICE, and in THIS file
      // a stray device of the learner account is not merely untidy -- it is a
      // third candidate in the election the scenario is about.
      await mx.logout(token);
    }
    if (mx.baseLang(code) === FIXTURE_LANG) continue;
    throw new Error(
      `${name} (${userId}) is learning ${code || 'nothing yet'}, and the `
      + `fixtures are ${FIXTURE_LANG}. Their half would come back empty however `
      + 'well the call went, and an empty half is the thing this scenario has '
      + 'to be able to tell a real merge failure apart from. Sign in as that '
      + `account and set the learning language to ${FIXTURE_LANG}.`,
    );
  }
}

/// Refuses two devices that would say the same thing.
///
/// Two microphones playing one file write two halves nobody can tell apart --
/// which is the exact shape of the merge failure this file exists to catch, so
/// every check would pass hardest at the moment the feature was most broken.
/// A refusal rather than a check, on the terms `browser.js` refuses a missing
/// wav: it is a fact about the rig, and naming the app for it would be a lie.
function refuseIfTheDevicesShareAVoice() {
  const fs = require('fs');
  const one = accounts.learnerFirstDevice.wav;
  const two = accounts.learnerSecondDevice.wav;
  if (one !== two && fs.existsSync(one) && fs.existsSync(two)) {
    const a = fs.readFileSync(one);
    const b = fs.readFileSync(two);
    if (!a.equals(b)) return;
  }
  throw new Error(
    `the learner's two devices would play the same audio (${one} and ${two}). `
    + 'Two halves of identical speech are indistinguishable, so a reader that '
    + 'kept one of them would pass every check in this file. Point '
    + 'CALL_LEARNER_TWO_WAV at a DIFFERENT wav of real English speech, containing '
    + `the words ${DEVICE_TWO_SAYS.join('/')} and none of `
    + `${DEVICE_ONE_SAYS.join('/')}.`,
  );
}

/// The transcript halves written since a mark. Read from the SERVER, and
/// identified by the harness's own since-a-mark mechanism rather than by
/// counting -- see `transcript.js` for why counting was wrong.
async function halvesSince(token, mark) {
  const events = await h.since(token, ROOM_ID, mark);
  return events.filter((e) => e.type === TRANSCRIPT);
}

/// Halves already in the room under [callKey], written before [before].
///
/// Asked of the room's history rather than of this run, because the thing it
/// is looking for is a call key an EARLIER call already used -- and an earlier
/// call may be one nobody here placed.
async function halvesUnder(token, callKey, before) {
  const events = await mx.timeline(token, ROOM_ID, 300);
  return events.filter(
    (e) => e.type === TRANSCRIPT
      && e.content?.call_key === callKey
      && (e.origin_server_ts || 0) < before,
  );
}

/// Which of the learner's devices JOINED this call, according to the server.
///
/// The union over every membership event the account wrote since the ring, and
/// NOT the current state -- which under-reports, measured here rather than
/// assumed. `com.famedly.call.member` is one state event per ACCOUNT holding a
/// list of that account's devices, so two devices answering in the same instant
/// each write the whole list from their own view: at 02:11:31.811 the second
/// device published a list containing only itself, and seven milliseconds later
/// the first published a list containing only ITSELF, and the room state kept
/// the later one. Both devices really were in the call -- both wrote a
/// transcript half for it -- while the state said one.
///
/// So the state is a snapshot that a race can lie in, and the timeline is the
/// record. Both are read: a device whose event has aged out of the window is
/// still in the state, and a device the state has lost is still in the
/// timeline.
async function joinedDevices(token, userId, mark) {
  const ids = new Set();
  for (const e of await h.since(token, ROOM_ID, mark)) {
    if (e.type !== MEMBER || e.sender !== userId) continue;
    for (const m of e.content?.memberships ?? []) {
      if (typeof m?.device_id === 'string' && m.device_id) ids.add(m.device_id);
    }
  }
  for (const d of await mx.liveMembershipDevices(token, ROOM_ID, userId)) {
    ids.add(d);
  }
  return [...ids];
}

/// Which of an account's devices `CaptureElection` gives the recording to.
///
/// A COPY of the product's rule, and the copy is deliberate: the harness has to
/// hang up the device that is RECORDING for the handover to put speech in both
/// halves, and nothing observable says which one that is until the call is over.
///
/// `CaptureElection._sortsBefore` is a total order -- capability first, device
/// id second -- and on this stack the capability term is constant: the LiveKit
/// token lacks CanUpdateOwnMetadata, so no device can publish an answer, every
/// device reads as ABLE, and the order reduces to the id. Lowest sorts first
/// and records. Dart's `String.compareTo` and JS's `<` are both UTF-16
/// code-unit order, so the two agree.
///
/// A PREDICTION, and it is never asserted on. What the run asserts is the
/// OUTCOME -- that both halves came back with speech in them -- so this being
/// wrong shows up as a failure naming the knob, not as a check that quietly
/// changes meaning.
const recorderAmong = (deviceIds) => [...deviceIds].sort()[0] ?? null;

/// How many devices the READER says it assembled a half from.
///
/// The app states this in one place and one place only: the read-time log in
/// `transcript_repo`, which prints `devices <n>` for every half that is not
/// clean. That is not a gap in the coverage -- it is the design. A half
/// assembled from more than one device is never clean (`deviceCount > 1` is the
/// last rung of `TranscriptHalf.issue`, so it is reported when nothing louder
/// is wrong and hidden by nothing when something is), so a merged half ALWAYS
/// produces the line and the line ALWAYS carries the count.
///
/// Which makes this the only check that can tell a merge from a reader that
/// kept one half, in the case the run reaches most often. `CaptureElection`
/// leaves one of the two halves empty whenever the handover did not move the
/// recording, and a screen drawn from {full, empty} is identical to a screen
/// drawn from {full} alone -- so the drawn-turn count says nothing there. This
/// says it anyway.
///
/// Scoped to THIS call and to the reader's own half: the room's timeline holds
/// a card for every call it has ever had, and a stale panel opening on one of
/// them would otherwise answer for it.
function mergeCountsIn(lines, callKey, role = 'self') {
  const counts = [];
  for (const line of lines) {
    if (!line.includes('Call transcript half not clean:')) continue;
    if (!line.includes(` for ${role} on ${callKey}`)) continue;
    const m = line.match(/devices (\d+)\)/);
    if (m) counts.push(Number(m[1]));
  }
  return counts;
}

/// Whether the reader's own log says a half was assembled from BOTH devices.
///
/// A count that never arrived is a FAILURE and not an abstention: a merged half
/// always writes the line, so an absent line means the reader either grouped by
/// sender or never read this call.
const provesTwoDeviceMerge = (counts) =>
  counts.length > 0 && Math.max(...counts) === 2;

/// Whether both of the account's halves carry speech.
///
/// The state the handover exists to reach. Without it the drawn-turn count
/// cannot tell a merge from a reader that dropped the empty half, so a run that
/// does not reach it has not tested what it says it tests.
const bothDevicesSpoke = (halves) =>
  halves.length === 2
  && halves.every((e) => (e.content?.segments?.length ?? 0) > 0);

/// Whether every half the call should produce actually arrived.
///
/// Two devices of the learner and one of the peer. A wait that ran out has not
/// learned that three was the wrong number -- it has learned nothing.
const allHalvesArrived = (written, expected = 3) => written.length >= expected;

/// Whether the two devices were SEEN sending under different transaction ids.
///
/// One distinct id each. A device with several has sent the same speech twice
/// under keys that do not collide; a device with none was not seen sending at
/// all, and that is the opposite finding from two ids that matched.
const sentUnderDifferentIds = (one, two) =>
  one.length === 1 && two.length === 1 && one[0] !== two[0];

/// Whether the ids that went out are exactly the ids the formula derives.
///
/// What keeps [txnIdOf] honest. If the app's formula changes and this file's
/// copy does not follow, these two sets part company and the run says so --
/// rather than carrying on comparing a rule the product has stopped using.
const idsSentMatchDerived = (observed, derived) =>
  observed.length > 0 && derived.length > 0
  && JSON.stringify([...observed].sort()) === JSON.stringify([...derived].sort());

/// Whether the server recorded a HANDOVER: one device gone, the other still in.
///
/// WHY IT IS NOT "the live count went down". The live membership state is a
/// snapshot a race can lie in -- `joinedDevices` measures it doing exactly that
/// -- so it can say ONE while two devices are in the call. Read that as a
/// baseline and the whole check collapses: state says one before the click, the
/// click misses, state still says one, and "one device left and the other
/// stayed" is reported off a server observable that never changed. That is the
/// shape this used to have.
///
/// So THREE things, and the first is the one that makes it a handover at all:
///
///   - the server wrote a NEW membership event for this account after the click
///     was asked for. Something changed; nothing here is read off a state that
///     was already in this shape.
///   - the device that was told to leave is gone from the live membership --
///     and it is a device the server saw JOIN this call, so its absence is a
///     departure rather than a device that was never there.
///   - a DIFFERENT device the server saw join is still in it.
///
/// [leaver] may be null when the browser could not be paired with a device id.
/// The fallback then demands what it can: a live set that really did shrink,
/// from a baseline observed to hold BOTH devices, down to exactly one of them.
/// It cannot be satisfied by a baseline that was already one, which is the
/// hole. If the baseline never held two, this refuses -- an unjudgeable state
/// is not a handover.
function handoverVerdict({ changed, live, leaver, joined, baseline }) {
  const inCall = [...(joined || [])];
  const now = [...(live || [])];
  if (!changed || !changed.length) {
    return {
      ok: false,
      why: 'the server recorded no new call-membership event for the account '
        + 'after the hangup was asked for, so nothing about the call changed',
    };
  }
  if (leaver) {
    if (!inCall.includes(leaver)) {
      return {
        ok: false,
        why: `the device told to leave (${leaver}) is not one the server saw `
          + `join this call (${JSON.stringify(inCall)})`,
      };
    }
    if (now.includes(leaver)) {
      return { ok: false, why: `${leaver} is still in the call (${JSON.stringify(now)})` };
    }
    const stayed = now.filter((d) => d !== leaver && inCall.includes(d));
    return {
      ok: stayed.length > 0,
      why: stayed.length
        ? ''
        : `${leaver} left, but no other device of the call is still in it `
          + `(${JSON.stringify(now)})`,
    };
  }
  const base = [...(baseline || [])];
  if (base.length < 2) {
    return {
      ok: false,
      why: 'the harness could not pair either browser with a device id, and the '
        + 'live membership never showed BOTH devices before the hangup '
        + `(${JSON.stringify(base)}) -- so a set that reads as one afterwards `
        + 'cannot be told from a set that already did',
    };
  }
  return {
    ok: now.length === 1 && base.includes(now[0]),
    why: now.length === 1 && base.includes(now[0])
      ? ''
      : `the live membership went from ${JSON.stringify(base)} to `
        + `${JSON.stringify(now)}, which is not one of those two devices left `
        + 'behind by the other',
  };
}

/// How many turns the transcript panel drew.
///
/// One timestamp per drawn segment, counted off the semantics tree because the
/// WORDS are not in it -- CanvasKit draws them and neither the page text nor a
/// semantics name carries one. The timestamps are there, and all of them:
/// Flutter does not clip its semantics to a scroll view, so a turn below the
/// fold still counts.
///
/// Counted INSIDE a node's name rather than by matching whole names, and that
/// is the whole of the difficulty. The engine publishes the panel's turn list
/// as ONE merged `aria-label` with the times separated by newlines, and
/// `ui.scan` splits only a node's own TEXT that way, never an attribute -- so a
/// filter on whole names matched nothing at all and reported a panel of
/// nineteen turns as empty. A check that always reads zero always fails, which
/// is the same worthlessness as one that always passes, from the other side.
///
/// The MAXIMUM over nodes rather than the sum, because a timestamp is not
/// unique to the panel: every call card behind the dialog carries its own
/// duration in the same shape. The transcript's node is the one holding all of
/// them, and a card's single stray time cannot beat it.
function countTurns(nodes) {
  let most = 0;
  for (const node of nodes) {
    const blob = node.names.join('\n');
    const times = blob.match(/(?:^|\n)\s*\d{1,2}:\d{2}\s*(?=$|\n)/g);
    if (times && times.length > most) most = times.length;
  }
  return most;
}

/// Opens the transcript of the NEWEST call card on screen.
///
/// `ui.clickControl` ranks its matches by whether a click can reach them and
/// takes the first, which is right for a control there is only one of. A
/// timeline holds a "Read the transcript" for EVERY call the room has ever had,
/// and the one a click could reach turned out to be a call from months back --
/// so the dialog opened, the check that a card offers the transcript passed,
/// and every word of the call under test was reported missing from a screen
/// that was never showing it.
///
/// The newest card is the LOWEST one: the timeline is bottom-anchored and the
/// room opens at the end of it. So the choice here is by position rather than
/// by rank, and it is made from the same scan every other click uses --
/// hittable only, for the reason [ui.choose] gives: a card scrolled out of the
/// list keeps a node at a coordinate that can sit over something else entirely.
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

/// Captures a page's console.
///
/// The app states how many devices a half was assembled from in its read-time
/// log and NOWHERE ELSE -- deliberately, because the multi-device fact must
/// never displace a specific true cause in front of a learner. So the log is
/// the only place this scenario can ask its third question, and it is a real
/// answer: the same line a bug report would be diagnosed from.
function captureConsole(participant) {
  const lines = [];
  participant.page.on('console', (m) => {
    try {
      lines.push(m.text());
    } catch (_) {
      // A diagnostic is never worth a dropped run.
    }
  });
  return lines;
}

/// Every browser this run launched, so nothing has to be in scope to close it.
///
/// The top-level catch is the reason: a throw anywhere leaves three Chromes
/// holding three profile locks, and the NEXT run then fails at its first line
/// with a message about the harness rather than about whatever went wrong here.
const opened = [];

/// Ends the run with nothing left running.
///
/// Chrome holds an exclusive lock on a profile directory, so a scenario that
/// exits over a browser it launched leaves the NEXT run dead at its first
/// line -- "the browser is already running for ..." -- which reads as a broken
/// harness rather than as the previous failure it actually is. Every screenshot
/// and every log this file keeps is written before it gets here, so nothing
/// diagnostic is lost by closing.
async function finish(participants, code) {
  for (const p of participants) {
    if (!p) continue;
    await p.browser.close().catch(() => {});
  }
  process.exit(code);
}

async function main() {
  const s = 'transcript-two-devices';
  console.log('[1] three browsers: the learner TWICE, and the other person');
  h.refuseIfAnotherRunIsLive();
  refuseIfTheDevicesShareAVoice();
  await refuseIfNotLearning(['learner', 'calltester']);

  // ALL THREE opened before anything rings, and that ordering is not
  // cosmetic. A ring lives thirty seconds. Opening the second device once the
  // call is already up would spend most of that window signing a browser in,
  // and the run would then report a product that refuses a second device when
  // what really happened is that the harness answered an EXPIRED ring.
  //
  // The send watcher goes on BEFORE the app loads, on both learner devices.
  // What it is for is in [installSendWatch]: the transaction id a send used
  // exists only in the request that carried it, and the account's own token is
  // the only way to ask which Matrix device a browser is.
  const watch = { prepare: watchSends };
  const A1 = await h.openParticipant('learnerFirstDevice', ROOM, 9741, watch);
  opened.push(A1);
  const A2 = await h.openParticipant('learnerSecondDevice', ROOM, 9742, watch);
  opened.push(A2);
  const B = await h.openParticipant('calltester', ROOM, 9743);
  opened.push(B);
  const logA1 = captureConsole(A1);
  const logA2 = captureConsole(A2);

  // WHICH DEVICE EACH BROWSER IS, before anything rings.
  //
  // Everything about the handover turns on it: which device to hang up (the one
  // holding the recording, or the other half of the call stays silent) and
  // whether the hangup did anything (the live state can say one while two are
  // in the call, so "one is left" is only a departure next to a NAMED device
  // that has gone). Polled rather than read once: the token appears with the
  // app's first authenticated request, which is a moment after the page is up.
  const deviceIds = { one: null, two: null };
  for (let i = 0; i < 20 && !(deviceIds.one && deviceIds.two); i++) {
    if (!deviceIds.one) deviceIds.one = await deviceOfPage(A1.page).catch(() => null);
    if (!deviceIds.two) deviceIds.two = await deviceOfPage(A2.page).catch(() => null);
    if (deviceIds.one && deviceIds.two) break;
    await wait(1500);
  }
  // Not a check, and deliberately not one. It is a fact about the RIG, and the
  // run is still worth having without it -- everything after this either uses
  // the pairing or says out loud that it could not.
  console.log(`   (device one is ${deviceIds.one || 'unidentified'}, ` +
    `device two is ${deviceIds.two || 'unidentified'})`);

  // The two accounts, named once. A1 and A2 are ONE account, so every
  // server-side question about "the learner" is asked with one token.
  const LEARNER = A1.userId;

  // Nothing of the learner's may be in a call before this one starts. A live
  // membership left behind by an earlier run is a THIRD device in the
  // election, and it would answer this scenario's central question with a
  // number that is nothing to do with what it drove.
  const before = await mx.liveMembershipDevices(A1.token, ROOM_ID, LEARNER);
  h.check(s, 'the learner starts with no device in a call', before.length === 0,
    `already in a call on ${before.length} device(s): ${before.join(', ')}`);
  if (before.length) { h.report(); await finish([A1, A2, B], 2); }

  console.log('[2] the peer calls, and BOTH learner devices answer at once');
  // WHY AT ONCE, and it is a fact about the product rather than a trick.
  //
  // The caller's own devices are not rung -- `shouldRing` drops a notification
  // whose sender is this account -- so the learner cannot be the one to place
  // it. The peer calls, both of the learner's devices ring, and then:
  // ANSWERING ON ONE STOPS THE OTHER. `answeredOnAnotherDevice` watches this
  // account's own call membership, and the moment a sibling's lands the other
  // device's prompt is dismissed. That is deliberate and it is the right
  // behaviour for a phone and a laptop ringing together -- but it means the
  // ring flow offers a second device NO WAY IN once the first has answered.
  //
  // So the state this file is about is reached exactly the way the product's
  // own code says it is reached: the convergence race that
  // `CaptureElection.discardsCapturedAudio` is written for -- "two of a
  // learner's devices answering the same call in the same instant each see a
  // roster that momentarily lacks the other". Both taps go out together, ahead
  // of the sync round trip that would put the second prompt away.
  //
  // A race is retried as a RACE. Once one device has joined, the other's
  // prompt is gone and no amount of clicking brings it back, so a failed
  // attempt is torn all the way down and the call is placed again.
  const attempts = 4;
  let inCall = [];
  let callKey = null;
  let attemptsUsed = 0;
  let reusedKey = null;
  for (let attempt = 1; attempt <= attempts; attempt++) {
    attemptsUsed = attempt;
    // Retried against the RING EVENT rather than against the click, which is
    // the suite's idiom: a call button pressed while a previous teardown is
    // still settling does nothing at all, with no error anywhere.
    const markRing = await h.mark(B.token, ROOM_ID);
    const rang = await h.actUntil(
      'place call',
      async () => {
        await h.ensureRoom(B, ROOM);
        await ui.clickControl(B.page, 'call').catch(() => {});
      },
      async () => (await h.since(B.token, ROOM_ID, markRing)).some(
        (e) => e.type === mx.RING && e.sender === B.userId,
      ),
      { tries: 4, gap: 4000 },
    );
    h.check(s, `the peer placing a call rang the learner (attempt ${attempt})`,
      rang, 'no ring event reached the room');
    if (!rang) { h.report(); await finish([A1, A2, B], 2); }

    // WHICH CALL THIS IS, straight off the ring. The call key is the caller's
    // membership event id, and the ring carries it as its reference -- so it is
    // knowable the moment the call starts, rather than only once a half has
    // been written under it. Everything this scenario reads later is scoped to
    // it.
    const ring = (await h.since(B.token, ROOM_ID, markRing))
      .find((e) => e.type === mx.RING && e.sender === B.userId);
    callKey = ring?.content?.['m.relates_to']?.event_id ?? null;

    // Both taps in flight together. PROVEN by the memberships, never by the
    // clicks: the ring banner is an overlay Flutter keeps out of the
    // accessibility tree, so it is driven positionally and a click that missed
    // looks exactly like one that worked.
    await Promise.all([
      ui.clickBanner(A1.page, 'answer').catch(() => {}),
      ui.clickBanner(A2.page, 'answer').catch(() => {}),
    ]);
    for (let i = 0; i < 12; i++) {
      inCall = await joinedDevices(A1.token, LEARNER, markRing);
      if (inCall.length >= 2) break;
      await wait(1000);
    }
    // A call key this room has already written a half under is a call whose
    // transcript is destroyed before it is written -- see [freshCallKey]. There
    // is nothing to learn from such a call, so the race is run again; the fact
    // that it happened is remembered and reported below rather than retried
    // away.
    const earlier = callKey
      ? await halvesUnder(A1.token, callKey, ring?.origin_server_ts ?? 0)
      : [];
    if (earlier.length) reusedKey = { callKey, earlier: earlier.length, attempt };
    if (inCall.length >= 2 && !earlier.length) break;

    console.log(`   (attempt ${attempt}: ${inCall.length} of the learner's ` +
      `devices got in${earlier.length ? ', and the call key was already used' : ''}` +
      '; tearing the call down and racing again)');
    // All the way down, and PROVEN down. A half-joined call left standing would
    // have the next ring suppressed as busy on one device and answered on the
    // other -- and, worse, a caller that never retracted its membership hands
    // the next call the SAME call key, which is the silent destroyer below.
    for (const p of [A1, A2, B]) {
      await h.actUntil(
        `teardown hangup for ${p.name}`,
        () => ui.clickPanel(p.page, 'hangup').then(() => {}, () => {}),
        async () => (p === B
          ? !(await mx.hasMembership(p.token, ROOM_ID, p.userId))
          : (await mx.liveMembershipDevices(p.token, ROOM_ID, LEARNER)).length === 0),
        { tries: 4, gap: 2500 },
      );
    }
    // And SETTLED. The caller anchors the next call on its own membership event
    // id, read from its local room state, so a call placed before the retract
    // has echoed back reuses the id the last call used.
    await wait(10000);
  }

  h.check(s, 'BOTH of the learner devices are in the one call',
    inCall.length >= 2,
    `the server saw ${inCall.length} of the learner's devices join ` +
      `(${inCall.join(', ') || 'none'}) across ${attemptsUsed} attempt(s). ` +
      'Nothing after this can be asked at all: one device in a call writes ' +
      'one half, and one half is what the keying this replaced already ' +
      'produced. What the second device said about the ring is in the log ' +
      'written below');

  // The silent destroyer, reported whether or not a later attempt got round it.
  //
  // The transcript transaction id is `(call key, sender, device)`, and this
  // homeserver collapses a repeated transaction id from the SAME device: the
  // second send returns the first event and writes nothing. So two calls that
  // share a call key are two calls of which only the FIRST has a transcript --
  // silently, with no error anywhere, and the second call's speech simply never
  // reaches the room.
  //
  // It is not hypothetical and it is not this file's doing: it was measured
  // here, on a redial two seconds after a hangup, where the caller rang with the
  // PREVIOUS call's membership event id. Reported as a failure rather than
  // retried away, because a scenario that quietly re-rolls until it gets a clean
  // call would hide exactly the thing a real-stack run is for.
  h.check(s, 'this call has a call key no earlier call already wrote under',
    reusedKey === null,
    reusedKey
      ? `attempt ${reusedKey.attempt} rang with call key ${reusedKey.callKey}, ` +
        `which ${reusedKey.earlier} earlier half/halves in this room already ` +
        'carry. Every writer in that call computes the transaction id it ' +
        'already used, the homeserver hands back the earlier event, and the ' +
        'whole of that call\'s transcript is lost with nothing logged'
      : '');

  if (inCall.length < 2) {
    await A1.page.screenshot({ path: shot('two-devices-nojoin-one.png') }).catch(() => {});
    await A2.page.screenshot({ path: shot('two-devices-nojoin-two.png') }).catch(() => {});
    // The second device's own account of what it did with the ring. Without
    // it, "a second device never joined" is a symptom with no cause attached,
    // and the two causes -- a tap that missed an overlay, and a prompt the app
    // deliberately put away -- want completely different fixes.
    const said = logA2.filter((l) => /ring|call|answer/i.test(l));
    console.log('   the second device said:');
    for (const line of said.slice(-15)) console.log(`     ${line}`);
    require('fs').writeFileSync(
      shot('two-devices-nojoin.log'),
      [...logA1, '', '=== second device ===', ...logA2].join('\n'),
    );
    console.log(`   (full log: ${shot('two-devices-nojoin.log')})`);
    h.report();
    await finish([A1, A2, B], 2);
  }
  console.log(`   (both devices in the call after ${attemptsUsed} attempt(s): ` +
    `${inCall.join(', ')}; call key ${callKey})`);

  // A SECOND mark, taken now rather than at the top. A race that had to be
  // retried placed a call that was torn down, and a torn-down call writes its
  // halves too -- so "two halves from the learner" would be satisfied by one
  // half from each of two DIFFERENT calls, which is the keying this file is
  // supposed to be able to refuse. Halves are written at the end of a call, so
  // everything this call produces is after this line.
  const mCall = await h.mark(A1.token, ROOM_ID);

  console.log('[3] talking, then a HANDOVER: one device leaves, the other records');
  // WHY A HANDOVER, and it is forced by the product rather than chosen.
  //
  // `CaptureElection` lets exactly ONE of an account's devices hold the
  // recording: they rank themselves by device id and the loser stands aside, so
  // two devices sitting in a call together produce one half with speech and one
  // with none. That is a real case and the checks above cover it -- but it
  // cannot tell a reader that MERGED the two halves from one that kept the
  // half with the words in it and threw the empty one away. Both draw the same
  // screen.
  //
  // Speech in BOTH halves is what separates them, and the only way to get it is
  // for the device holding the recording to leave: the election re-runs, the
  // survivor takes over, and the two halves then carry different stretches of
  // the same call. That is also a flow a learner really has -- picking the call
  // up on a phone and closing the laptop.
  //
  // Which device holds the recording is decided by a device id neither this
  // file nor anyone else chooses -- so the run works out WHICH and hangs that
  // one up, rather than picking a side and reporting whichever case it got.
  // The outcome is checked either way: a run that ends with one half empty
  // fails on `BOTH of the learner devices transcribed`, because the screen it
  // leaves is the screen a reader that dropped the empty half also draws.
  await wait(35000);

  // WHICH device leaves, and it is WORKED OUT rather than tossed for.
  //
  // It has to be the one holding the recording, or the survivor never takes
  // over and the other half stays empty. `CaptureElection` ranks on the device
  // id, lowest first, and this stack cannot publish the capability term at all
  // -- so the recorder is simply the lower of the two ids the server saw join
  // ([recorderAmong]). Pairing that id with a BROWSER is the part that needed
  // machinery, and it has it: [deviceOfPage] asks the homeserver with the
  // browser's own token, above, before anything rings.
  //
  // CALL_HANDOVER_DEVICE still forces a side, for a stack where that reasoning
  // does not hold. It selects a DEVICE and never an outcome: whichever way the
  // pick goes, `BOTH of the learner devices transcribed` is asked afterwards
  // and FAILS on one empty half. A wrong pick is a red run naming the knob, not
  // a check that quietly changes what it means.
  const forced = process.env.CALL_HANDOVER_DEVICE;
  const predicted = recorderAmong(inCall);
  const paired = deviceIds.one && deviceIds.two
    ? (predicted === deviceIds.two ? 'two' : 'one')
    : null;
  const leaverName = forced
    ? (forced === 'two' ? 'two' : 'one')
    : (paired || 'one');
  const leaver = leaverName === 'two' ? A2 : A1;
  const leaverDevice = deviceIds[leaverName];
  console.log(`   device ${leaverName} (${leaverDevice || 'unidentified'}) leaves; ` +
    'the other should pick the recording up' +
    (forced ? ' -- chosen by CALL_HANDOVER_DEVICE' : '') +
    (paired && !forced ? ` -- it holds ${predicted}, the lower of the two ids` : '') +
    (!paired && !forced ? ' -- A GUESS: neither browser could be paired with a device id' : ''));

  // The baseline the fallback needs, and it is POLLED rather than read once.
  // The live state under-reports during the join race (see [joinedDevices]); by
  // now the devices have been in the call for thirty-five seconds and it should
  // have caught up, but "should" is not a measurement. Whatever it ends up
  // holding is what [handoverVerdict] is handed, and a baseline that never
  // showed two is a baseline it refuses to conclude from.
  let baseline = [];
  for (let i = 0; i < 8; i++) {
    baseline = await mx.liveMembershipDevices(A1.token, ROOM_ID, LEARNER);
    if (baseline.length >= 2) break;
    await wait(2000);
  }
  // Taken BEFORE the click, so "the server wrote a new membership event" means
  // one that this hangup could have caused.
  const mHandover = await h.mark(A1.token, ROOM_ID);
  const observe = async () => handoverVerdict({
    changed: (await h.since(A1.token, ROOM_ID, mHandover))
      .filter((e) => e.type === MEMBER && e.sender === LEARNER),
    live: await mx.liveMembershipDevices(A1.token, ROOM_ID, LEARNER),
    leaver: leaverDevice,
    joined: inCall,
    baseline,
  });
  const handed = await h.actUntil(
    `device ${leaverName} leaves mid-call`,
    () => ui.clickPanel(leaver.page, 'hangup').then(() => {}, () => {}),
    async () => (await observe()).ok,
    { tries: 4, gap: 3000 },
  );
  const verdict = await observe();
  const stillIn = await mx.liveMembershipDevices(A1.token, ROOM_ID, LEARNER);
  console.log(`   (after the handover the call holds ${JSON.stringify(stillIn)})`);
  h.check(s, 'one device left and the other stayed in the call', handed,
    `${verdict.why || 'the handover was not observed'}. The learner holds ` +
      `${JSON.stringify(stillIn)}; the server saw ${JSON.stringify(inCall)} ` +
      `join, and the live membership read ${JSON.stringify(baseline)} before ` +
      'the hangup. Either the device that was told to leave never did, or ' +
      'both did, and neither leaves the survivor recording a stretch of its own');

  // Long enough for the survivor's own fixture to be transcribed. Its wav
  // repeats the same sentences three times over precisely so that this
  // stretch -- whichever stretch it turns out to be -- has words in it.
  await wait(HANDOVER_TAIL_MS);

  console.log('[4] the rest of the call ends, then the drain settles');
  // ASKED OF THE ACCOUNT, not of each device, and that is forced by the shape
  // of the state rather than chosen. `com.famedly.call.member` is one row per
  // ACCOUNT, so "did THIS device leave" is not a question it can answer: the
  // row that remains says the account is still in the call, and it says the
  // same thing whichever device is left. A first version asked it per device
  // and failed on a hangup that had plainly worked -- the count it compared
  // against was itself a snapshot of a race (see [joinedDevices]).
  //
  // Both taps every round, retried against the account's memberships being
  // gone. Clicking a hangup that has already happened is harmless; a device
  // still in the call after five rounds is not.
  const learnerLeft = await h.actUntil(
    'hang up both learner devices',
    async () => {
      await ui.clickPanel(A1.page, 'hangup').catch(() => {});
      await ui.clickPanel(A2.page, 'hangup').catch(() => {});
    },
    async () =>
      (await mx.liveMembershipDevices(A1.token, ROOM_ID, LEARNER)).length === 0,
    { tries: 5, gap: 3000 },
  );
  h.check(s, 'both learner devices left the call', learnerLeft,
    'the learner still holds ' +
      `${(await mx.liveMembershipDevices(A1.token, ROOM_ID, LEARNER)).length} ` +
      'live membership(s), so at least one device never hung up and its half ' +
      'has not been written yet');
  // The peer's hangup is a step, not a gesture: its half is written when it
  // leaves, so a peer still in the call is a third half that never arrives --
  // and the wait below would then run its full two minutes and carry on.
  // Ignoring this result is how that came to look like a slow homeserver.
  const peerLeft = await h.actUntil(
    'hangup on the peer',
    () => ui.clickPanel(B.page, 'hangup'),
    async () => !(await mx.hasMembership(B.token, ROOM_ID, B.userId)),
  );
  h.check(s, 'the peer left the call', peerLeft,
    'the peer still holds a live call membership, so it has not drained and ' +
      'its half of the transcript will not be written at all');

  // The halves are written after the drain, not at hangup, so this waits for
  // the SERVER to have them rather than sleeping a guessed interval. Three are
  // expected -- two devices of the learner and one of the peer -- and the loop
  // waits for the third rather than stopping at two, so "two halves" is never
  // satisfied by one learner half plus the peer's.
  //
  // WHAT THE LOOP RUNNING OUT MEANS is asserted below rather than shrugged off.
  // It used to fall through: two learner halves arrive, the peer's never does,
  // every learner-side check passes, the comparison against the peer skips on
  // empty words, and the run exits green on a call that half failed. A wait
  // that expires has not learned that three halves is the wrong number -- it
  // has learned nothing, and nothing is not a pass.
  const waitRounds = 40;
  const roundMs = 3000;
  let written = [];
  let rounds = 0;
  for (let i = 0; i < waitRounds; i++) {
    rounds = i + 1;
    written = await halvesSince(A1.token, mCall);
    if (written.length >= 3) break;
    await wait(roundMs);
  }

  console.log('[5] what reached the room');
  const mine = written.filter((e) => e.sender === LEARNER);
  const theirs = written.filter((e) => e.sender === B.userId);
  // The raw halves, kept. Every check below is a sentence about these events,
  // and a failure that cannot be re-read against the bytes that caused it is a
  // failure somebody has to reproduce before they can start on it.
  require('fs').writeFileSync(
    shot('two-devices-halves.json'),
    JSON.stringify(
      { callKey, inCall, halves: written },
      null,
      1,
    ),
  );
  console.log(`   (${written.length} half/halves: ${mine.length} learner, ` +
    `${theirs.length} peer)`);

  // THE WAIT'S OWN RESULT, said out loud. Everything below reads the halves
  // that arrived; a run that gave up waiting for one of them is reading a
  // partial call, and each check that then passes passes about less than it
  // names.
  h.check(s, 'all three halves reached the room before the wait ran out',
    allHalvesArrived(written),
    `${written.length} half/half(s) after ${Math.round(rounds * roundMs / 1000)}s ` +
      `of waiting for three (${mine.length} learner, ${theirs.length} peer). ` +
      'Two devices of the learner and one of the peer each write one at the ' +
      'end of the call, so a missing half is a device that never drained -- ' +
      `the raw events are in ${shot('two-devices-halves.json')}`);

  // The peer's, specifically. `mine.length === 2` below says nothing about it,
  // and the cross-account check at the end is worthless without it.
  h.check(s, 'the peer wrote exactly one half', theirs.length === 1,
    `${theirs.length} half/halves from the peer, not 1`);

  // Every half belongs to the SAME call. The mark above should already
  // guarantee it, and this is what says so out loud: a half from an earlier,
  // abandoned attempt would otherwise stand in for the second device's, and
  // the check below would read a keying failure as a success.
  const keys = new Set(written.map((e) => e.content?.call_key));
  h.check(s, 'every half belongs to the one call', keys.size === 1,
    `${keys.size} call key(s) among ${written.length} half/halves: ` +
      `${JSON.stringify([...keys])}`);

  // ONE. This is the assertion the whole file is for. Under the keying this
  // replaced there was one half per ACCOUNT, and the second device's speech
  // was destroyed on the way to the screen.
  h.check(s, 'the account wrote a half from EACH of its two devices',
    mine.length === 2,
    `${mine.length} half/halves from the learner, not 2` +
      (mine.length
        ? ` (devices ${mine.map((e) => JSON.stringify(e.content?.device_id)).join(', ')})`
        : ''));

  const ids = mine.map((e) => e.content?.device_id);
  const named = ids.filter((d) => typeof d === 'string' && d.length > 0);
  h.check(s, 'each half NAMES the device that wrote it',
    named.length === mine.length && mine.length > 0,
    `device ids on the wire: ${JSON.stringify(ids)} -- a half that names no ` +
      'device keys alike with every other half that named none, which is the ' +
      'grouping the fix exists to break');
  h.check(s, 'the two halves name DIFFERENT devices',
    new Set(named).size === mine.length && mine.length > 0,
    `device ids on the wire: ${JSON.stringify(ids)}`);

  // And those are the devices that were actually in the call. Two distinct ids
  // are not enough on their own: a writer inventing them, or naming a device
  // from a previous call, would satisfy the check above and be a worse bug
  // than the one it replaced.
  h.check(s, 'the halves name the devices the server saw in the call',
    named.length > 0 && named.every((d) => inCall.includes(d)),
    `halves name ${JSON.stringify(named)}; the call had ` +
      `${JSON.stringify(inCall)}`);

  // TWO. THE IDS THE PRODUCT ACTUALLY SENT UNDER.
  //
  // Read off the two browsers' own outgoing requests -- the PUT path carries
  // the transaction id and nothing else ever does, because the server echoes it
  // back only to the sending device's sync and the harness holds a different
  // device's token. See [installSendWatch].
  //
  // This is the check the file used to only LOOK like it had. What stood here
  // recomputed the id from the events that arrived, which cannot witness a
  // send: an app regressed to the old `(call key, sender)` formula, on a
  // homeserver that happened to accept both requests, lands two events a
  // recomputation derives two distinct ids from -- and the check passes at the
  // exact moment the product is doing the thing this file exists to catch. The
  // recomputation is still asked, below, under a name that says what it is.
  let sends = { one: [], two: [], error: null };
  try {
    sends = {
      one: transcriptSendsOf(await sentBy(A1.page)),
      two: transcriptSendsOf(await sentBy(A2.page)),
      error: null,
    };
  } catch (e) {
    sends.error = e && e.message ? e.message : String(e);
  }
  const sentIds = {
    one: [...new Set(sends.one.map((r) => r.txnId))],
    two: [...new Set(sends.two.map((r) => r.txnId))],
  };
  console.log(`   (transcript sends seen on the wire: one ` +
    `${JSON.stringify(sentIds.one)}, two ${JSON.stringify(sentIds.two)})`);

  // A device that sent no half at all cannot be compared, and saying so here
  // rather than further down keeps "the harness saw nothing" apart from "the
  // two ids matched" -- opposite findings that a single check would blur.
  h.check(s, 'each learner device was seen SENDING a transcript half',
    !sends.error && sentIds.one.length === 1 && sentIds.two.length === 1,
    sends.error
      ? `the send log could not be read: ${sends.error}`
      : `device one sent ${sends.one.length} transcript half/halves under ` +
        `${sentIds.one.length} distinct transaction id(s), device two sent ` +
        `${sends.two.length} under ${sentIds.two.length}. One each is what a ` +
        'call produces; a device with several DISTINCT ids has sent the same ' +
        'speech twice under keys that do not collide, and a device with none ' +
        'either never wrote or wrote through a transport this does not watch');

  h.check(s, 'the two halves were SENT under DIFFERENT transaction ids',
    sentUnderDifferentIds(sentIds.one, sentIds.two),
    `device one sent under ${JSON.stringify(sentIds.one)}, device two under ` +
      `${JSON.stringify(sentIds.two)} -- one key for two devices, so a resend ` +
      'collapse and a second device are the same event to the server, and the ' +
      'homeserver keeps whichever arrived first');

  // AND THE ID THAT WENT OUT IS THE ID THIS FILE'S COPY OF THE FORMULA MAKES.
  //
  // Ties the two observables together, and it is what stops the recomputation
  // below from drifting into meaning something else: if `CallTranscriptContent.
  // txnId` changes and [txnIdOf] does not follow, these two sets stop matching
  // and the file says so, rather than carrying on comparing a formula the
  // product no longer uses.
  const txns = mine.map(txnIdOf);
  const observed = [...sentIds.one, ...sentIds.two].sort();
  h.check(s, 'each id sent is the one the app\'s formula makes for that half',
    idsSentMatchDerived(observed, txns),
    `sent ${JSON.stringify(observed)}; derived from the events that arrived ` +
      `${JSON.stringify([...txns].sort())}. They have to be the same set: if ` +
      'they are not, either a half arrived from a device that sent under a ' +
      'different key, or this file\'s copy of the formula has fallen behind ' +
      'the app\'s');

  // And the weaker sentence, kept and NAMED as the weaker sentence. It is about
  // the events, not about the sends: it fails when a half reaches the room with
  // no device id on it, which is the pre-fix world, and it is the only form the
  // check can take for a client whose sends nothing watched.
  h.check(s, 'the halves carry enough to DERIVE different transaction ids',
    new Set(txns).size === mine.length && mine.length > 0,
    `both derived to ${JSON.stringify(txns[0])} -- one key for two devices, ` +
      'so a resend collapse and a second device are the same event to the ' +
      'server');

  // And they are two events, not one. The distinct ids above are a statement
  // about the KEY; this is the outcome, and the two are worth asking
  // separately because only the second is what a person would notice.
  // Guarded on there BEING halves, and the guard is not decoration: a run that
  // produced none passed this check, because no events are trivially distinct.
  // That is a check that passes hardest when the feature is most broken, which
  // is the one shape this suite refuses.
  h.check(s, 'the two halves are two distinct events',
    mine.length > 0 && new Set(mine.map((e) => e.event_id)).size === mine.length,
    `event ids: ${JSON.stringify(mine.map((e) => e.event_id))}`);

  // AND THE SURVIVOR RECORDED THE REST OF IT.
  //
  // The handover is only a handover if the device that stayed picked the
  // recording up: `CaptureElection` re-runs whenever the roster changes, and
  // with its only sibling gone the survivor ranks first and records. A survivor
  // that captured NOTHING means the learner went on talking into a call that
  // nobody was recording, for as long as the call lasted.
  //
  // Asked only when a device really did leave one behind, and asked of the
  // COUNTS rather than of the words: a survivor that captured chunks and could
  // not transcribe them is a different failure from one that never opened a
  // recorder at all, and only the counts tell them apart.
  const survivorHalf = handed
    ? mine.find((e) => stillIn.includes(e.content?.device_id))
    : null;
  if (!handed) {
    h.skipped(s, 'the device that stayed recorded the rest of the call',
      'no handover happened, so no device was left to take the recording over');
  } else if (!survivorHalf) {
    // A FAILURE, not a shrug. Every fact this needs is proved above by a check
    // of its own -- the account wrote two halves, each NAMES its device, and
    // those devices are the ones the server saw in the call -- so once a device
    // has stayed, one of the halves is its. No half matching it means one of
    // those checks is lying or the device that stayed wrote nothing, and both
    // are findings. It used to skip here, which reported the pre-keying world
    // (a half naming no device) as a question rather than as the answer.
    h.check(s, 'the device that stayed recorded the rest of the call', false,
      `a device stayed (${stillIn.join(', ')}) but no half names it ` +
        `(${JSON.stringify(mine.map((e) => e.content?.device_id))}). The ` +
        'survivor either wrote no half at all, or wrote one that names a ' +
        'device the server never saw in this call');
  } else {
    const captured = survivorHalf.content?.chunks_captured ?? 0;
    h.check(s, 'the device that stayed recorded the rest of the call',
      captured > 0,
      `the surviving device ${survivorHalf.content?.device_id} captured ` +
        `${captured} chunk(s) in the ${HANDOVER_TAIL_MS / 1000}s it held the ` +
        'call alone, and refused nothing (captureRefused ' +
        `${survivorHalf.content?.capture_refused}, lost ` +
        `${survivorHalf.content?.chunks_lost}, dropped ` +
        `${survivorHalf.content?.capture_dropped_ms}ms). Everything said after ` +
        'the other device left went unrecorded. NOTE the one local condition ' +
        'that could explain it: this stack\'s LiveKit token lacks ' +
        'CanUpdateOwnMetadata, and the app says so itself -- "the recorder ' +
        'election is running without its capability layer" is in the log ' +
        'written below on every run here');
  }

  console.log('[6] which device said what');
  const byDevice = new Map();
  for (const e of mine) byDevice.set(e.content?.device_id ?? '<none>', words(spoken(e)));
  for (const [device, w] of byDevice) {
    console.log(`   ${device}: ${w.size} word(s) -- ${[...w].slice(0, 10).join(' ')}`);
  }
  const allMine = new Set([...byDevice.values()].flatMap((w) => [...w]));
  // Which device's fixture ended up where. The two learner devices play
  // DIFFERENT audio precisely so this is answerable at all -- without it, a
  // half from the wrong device and a half from the right one are the same
  // event.
  const spokeOne = DEVICE_ONE_SAYS.filter((w) => allMine.has(w));
  const spokeTwo = DEVICE_TWO_SAYS.filter((w) => allMine.has(w));
  console.log(`   device one's fixture: ${JSON.stringify(spokeOne)}; ` +
    `device two's: ${JSON.stringify(spokeTwo)}`);
  const halvesWithWords = mine.filter((e) => words(spoken(e)).size > 0);

  // A run where NEITHER learner device transcribed anything cannot judge the
  // rest, and must say so rather than passing: an empty screen is consistent
  // with a perfect merge of two empty halves.
  h.check(s, 'at least one learner device transcribed what it heard',
    halvesWithWords.length > 0,
    'both halves came back with no words at all, so nothing after this can ' +
      'tell a merge that kept everything from one that kept nothing. Check ' +
      'the fixtures reached Chrome and that speech-to-text answered');

  // AND THE STATE THE SCENARIO IS FOR: two halves that BOTH carry speech.
  //
  // A FAILURE when it is not reached, and this is the rule the rest of the file
  // is written to. With one half empty, the drawn-turn count below cannot tell
  // a reader that merged both halves from one that kept the full one and threw
  // the empty one away -- the two draw the same screen. That is not a pass with
  // a caveat; it is a run that did not reach the state it exists to test, and
  // the only honest report is a red one.
  //
  // It is reachable by construction rather than by luck: the handover hangs up
  // the device holding the recording, which the run works out from the ids the
  // server saw join. It fails when that pairing could not be made and the coin
  // came down the other way -- and then the message says which knob to turn.
  h.check(s, 'BOTH of the learner devices transcribed a stretch of the call',
    bothDevicesSpoke(mine),
    `turns per half: ${mine
      .map((e) => `${e.content?.device_id}=${e.content?.segments?.length ?? 0}`)
      .join(', ') || 'none'}. CaptureElection lets only the device holding the ` +
      'recording capture, so speech in both halves takes the RECORDER leaving ' +
      `at the handover -- device ${leaverName} left, and the recorder is the ` +
      `lower of ${JSON.stringify([...inCall].sort())}, which is ${predicted}. ` +
      (paired
        ? `Device ${leaverName} is ${leaverDevice}, so the pick was right and ` +
          'the empty half is the product, not the rig'
        : 'Neither browser could be paired with a device id, so the leaver was ' +
          'a guess: set CALL_HANDOVER_DEVICE to the other one and run again') +
      '. Until both halves carry speech the drawn-turn check below cannot tell ' +
      'a merge from a reader that dropped the empty half');

  console.log('[7] and what the screen says about it');
  // WHAT CAN BE READ OFF THIS SCREEN, AND WHAT CANNOT.
  //
  // The transcript panel is drawn by CanvasKit, and a turn's WORDS reach
  // neither the accessibility tree nor the page text: measured here, with the
  // panel plainly showing six sentences while `document.body.innerText` and
  // every `flt-semantics` name between them carried none of them. A check
  // written on the words is therefore a check that can only ever fail, and one
  // written on their absence -- "nobody who spoke is reported as silent" -- is
  // a check that can only ever pass. This file had both, and neither was
  // saying anything.
  //
  // What DOES reach the tree is every turn's own timestamp, one per drawn
  // segment, and all of them: Flutter does not clip its semantics to a scroll
  // view, so a turn below the fold is still in the tree. Counting them asks
  // the question this file actually needs -- was every turn either device
  // wrote drawn -- and it can fail, because a reader that kept one half draws
  // that half's turns and no others.
  await h.ensureRoom(A1, ROOM);
  // The semantics tree is thrown away with the document on any navigation, and
  // a tree that is not there answers "no card" for a card that is.
  await ui.enableSemantics(A1.page).catch(() => {});
  const card = await ui.hasControl(A1.page, 'transcriptLink').catch(() => false);
  const seen = card ? [] : await ui.labels(A1.page).catch(() => []);
  h.check(s, 'the card offers the transcript', card,
    'no way in to the transcript from the call card; on screen: ' +
      JSON.stringify((Array.isArray(seen) ? seen : []).slice(0, 25)));

  let turnsDrawn = 0;
  let dialogOpen = false;
  if (card) {
    await openNewestTranscript(A1.page);
    await wait(6000);
    await A1.page.screenshot({ path: shot('two-devices-transcript.png') }).catch(() => {});
    // The dialog's own title, from the page TEXT rather than from a label --
    // `transcript.js` reads its consent notice the same way and for the same
    // reason. Prose is not required to be in the accessibility tree, and this
    // one happens to be there.
    const text = await A1.page
      .evaluate(() => document.body.innerText || '')
      .catch(() => '');
    const titles = labels.labelsFor('callTranscriptTitle').filter(Boolean);
    dialogOpen = titles.some((t) => text.includes(t));
    turnsDrawn = countTurns(await ui.scan(A1.page));
    // Kept, because "the screen drew four turns and the room holds nineteen"
    // is a sentence somebody has to be able to check, and a screenshot cannot
    // be grepped.
    require('fs').writeFileSync(
      shot('two-devices-panel.txt'),
      `${(await ui.labels(A1.page)).join(' | ')}\n\n=== page text ===\n${text}`,
    );
  }
  h.check(s, 'the transcript dialog opened', dialogOpen,
    'the panel never appeared, so nothing below is a statement about the ' +
      'product. The labels and the page text are in the file named above');

  // THREE. THE READER MERGED THEM, AND THIS IS WHERE THAT IS PROVED.
  //
  // Not on the screen. The drawn-turn count below is a real check and it can
  // fail, but it is blind in the one direction that matters most: a reader that
  // dropped an EMPTY half draws exactly the screen a reader that merged it
  // draws. `CaptureElection` produces an empty half whenever one device holds
  // the recording for the whole call, so that is not a corner -- it is the
  // ordinary outcome, and for as long as this was the only reader-level check
  // the file's central claim rested on a screenshot somebody read by eye.
  //
  // The count is in the app's read-time log and nowhere else, by design: it may
  // never displace a specific true cause in front of a learner, so it is a
  // diagnostic rather than a sentence on screen. It is also unconditional
  // there -- a half assembled from more than one device is never "clean", so
  // the line is always written and always carries the number. See
  // [mergeCountsIn].
  //
  // POLLED, because the read is a network round trip the dialog starts and six
  // seconds is a guess about a machine. A count that never arrives fails: the
  // reader either did not merge or did not read, and both are findings.
  let merged = [];
  for (let i = 0; i < 10 && !merged.length; i++) {
    merged = mergeCountsIn(logA1, callKey);
    if (merged.length) break;
    await wait(2000);
  }
  h.check(s, "the reader assembled the account's half from BOTH devices",
    provesTwoDeviceMerge(merged),
    merged.length
      ? `the reader says it assembled the learner's half from ` +
        `${JSON.stringify(merged)} device(s). Two halves reached the room from ` +
        'two devices; a half assembled from one of them is the destroyed-half ' +
        'bug this whole change is about, drawn on a screen that looks complete'
      : `no "Call transcript half not clean: ... devices N" line for ` +
        `${callKey} on the reading device. A half assembled from two devices ` +
        'always writes one, so either the reader grouped by sender and saw a ' +
        'single device, or it never read this call at all -- check that the ' +
        'panel opened on the NEWEST card. The full log is written below');

  // THE ASSERTION THE READER HALF OF THIS FIX EXISTS FOR.
  //
  // Every turn every half carries has to be drawn. A reader that grouped by
  // sender keeps ONE of an account's halves, so the screen is short by exactly
  // the number of turns the half it dropped was carrying -- which is what this
  // counts.
  //
  // ASKED EVERY RUN, including the ones where one half is empty. It used to
  // stand aside there, on the grounds that an empty half being dropped leaves
  // the same screen -- true, and not a reason to stop asking: the check still
  // catches a reader that dropped the FULL half, and a run that reported it as
  // its only reader-level result and then exited 0 is what this file has just
  // been rewritten out of. Whether the run reached the state where this can
  // tell both directions apart is a separate check, above, and it FAILS when it
  // did not; the merge itself is proved off the reader's own log.
  const segmentsWritten = written.reduce(
    (n, e) => n + (e.content?.segments?.length ?? 0),
    0,
  );
  const learnerSegments = mine.reduce(
    (n, e) => n + (e.content?.segments?.length ?? 0),
    0,
  );
  if (!dialogOpen) {
    h.skipped(s, 'every turn either device wrote is drawn',
      'the panel never opened, so what it drew says nothing -- and the check ' +
        'above says that in red');
  } else {
    h.check(s, 'every turn either device wrote is drawn',
      turnsDrawn >= segmentsWritten,
      `${turnsDrawn} turn(s) drawn for ${segmentsWritten} written ` +
        `(${learnerSegments} of them the learner's, across ` +
        `${mine.length} device(s): ${mine
          .map((e) => `${e.content?.device_id}=${e.content?.segments?.length ?? 0}`)
          .join(', ')}). A reader that keeps one of an account's halves draws ` +
        'exactly this: short by the turns of the half it dropped');
  }

  // The peer is here to make the call a call, and its half is checked only for
  // the one thing that would invalidate everything above: a merge that reached
  // across ACCOUNTS would put the peer's words under the learner and this file
  // would read it as a successful device merge.
  //
  // ONE CHECK, and it fails on an empty comparison as well as on a crossing.
  // Splitting the two put "there was nothing to compare" in the SKIP column,
  // where it cost nothing: a peer whose half came back wordless -- which is
  // exactly what a peer that never drained produces -- turned the only
  // cross-account check in the file into a line nobody reads.
  const peerWords = new Set(theirs.flatMap((e) => [...words(spoken(e))]));
  const crossed = PEER_SAYS.filter((w) => allMine.has(w));
  h.check(s, "the peer's speech did not end up under the learner",
    peerWords.size > 0 && allMine.size > 0 && crossed.length === 0,
    crossed.length
      ? `the learner's half carries the peer's words ${crossed.join(' ')} -- the `
        + 'merge crossed accounts, not devices'
      : `nothing to compare: the learner has ${allMine.size} word(s), the peer `
        + `${peerWords.size}. A comparison against an empty set cannot find a `
        + 'crossing, so it may not report one was ruled out');

  console.log('[8] no unhandled errors on any of the three');
  for (const p of [A1, A2, B]) {
    h.check(s, `${p.name} had no unhandled errors`, p.errors.length === 0,
      JSON.stringify(p.errors.slice(0, 3)));
  }

  // Kept for the report: a run that failed on the screen is diagnosed from
  // what the reader said about every half, and that is not in any screenshot.
  const logPath = shot('two-devices-read.log');
  require('fs').writeFileSync(
    logPath,
    [...logA1, '', '=== second device ===', ...logA2].join('\n'),
  );
  console.log(`   (the reader's own log: ${logPath})`);

  // The exit code is the result, and NOT KNOWING IS NOT SUCCESS.
  //
  // `h.report()` counts the failures. It does not count the inconclusive
  // checks, and for anything reading an exit code that made a skip free: a run
  // in which the only reader-level check stood aside, having established
  // nothing about the merge this file exists to prove, exited 0 and read as
  // green. A check that could not be asked has not passed -- it has not
  // happened -- so both columns are counted here.
  //
  // Scoped to this scenario's own results because `h.inconclusive` is the
  // harness's, shared with every other file that imports it.
  const failed = h.report();
  const unproven = h.inconclusive.filter((i) => i.scenario === s).length;
  if (unproven) {
    console.log(`\n${unproven} check(s) proved nothing this run, and this run ` +
      'is therefore not green');
  }
  await finish([A1, A2, B], failed === 0 && unproven === 0 ? 0 : 1);
}

// Nothing runs on `require`. The predicates below are exported so the decisions
// this file makes -- what counts as a handover, what the reader's log says, what
// the wire says a transaction id was -- can be exercised directly against the
// inputs that used to slip past them, without three browsers and a two-minute
// call. A check nobody can make fail on demand is a check nobody has tested.
if (require.main === module) {
  main().catch(async (e) => {
    console.error('FAILED', e && e.message ? e.message : e);
    await finish(opened, 1);
  });
}

module.exports = {
  txnIdOf,
  transcriptSendsOf,
  recorderAmong,
  mergeCountsIn,
  provesTwoDeviceMerge,
  bothDevicesSpoke,
  allHalvesArrived,
  sentUnderDifferentIds,
  idsSentMatchDerived,
  handoverVerdict,
  countTurns,
  spoken,
  words,
};
