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
// FIVE THINGS, and each is asked of the SERVER, of the WIRE, or of the SCREEN,
// never of the click that was supposed to cause it.
//
//   1. BOTH HALVES SURVIVE. Two `pangea.call_transcript` events from the ONE
//      account, carrying DIFFERENT device ids -- and those two ids are the two
//      devices the server itself says were in the call.
//   2. THE TWO DEVICES SAID DIFFERENT THINGS. Each half carries the words of
//      one fixture and none of the other's, and the half naming the device a
//      browser authenticates as carries the wav THAT browser plays. Without
//      this the rest is arithmetic about two events that might hold the same
//      speech -- which is the shape of the very bug being tested for.
//   3. THE TRANSACTION IDS DIFFER, EACH HALF NAMES ITS OWN WRITER, AND THE
//      PRODUCT'S OWN IDS ARE THE ONES COMPARED. Matrix never sends a
//      transaction id back down, so it is taken from the OUTGOING request each
//      browser made -- the PUT path the app itself built -- and matched, PER
//      BROWSER, to the arrived half the app's formula derives it from and to
//      the device the homeserver says that browser is. Compared as sets instead
//      it proves two valid ids exist and nothing about which browser sent
//      which, and a build with the two ids swapped over passes.
//   4. THE READER MERGED THEM. Read off the app's own read-time log, which
//      states how many devices a half was assembled from -- the one place the
//      count is visible, and the only proof that survives the ordinary case
//      where `CaptureElection` left one of the two halves empty. A drawn-turn
//      count cannot tell a merge from a reader that dropped an empty half;
//      this can, so it is the check the merge rests on rather than the screen.
//   5. NOTHING IS LOST. The panel draws at least as many turns as the halves
//      carry, and none of the peer's own fixture words -- proven to be in the
//      peer's half first, or the search is over words nobody spoke -- end up
//      under the learner.
//
// AND EVERY ONE OF THEM FAILS WHEN IT CANNOT BE ASKED. A check that reports
// SKIP, and a wait that runs out and carries on, are both ways of not knowing,
// and not knowing is not success: the exit code counts an inconclusive check
// exactly as it counts a failed one (see the end of [main]). This file exited 0
// once while its central claim -- that the reader merges -- had proved nothing
// at all, because the only check that spoke to it skipped.
//
// AND EVERY CHECK PROVES THE CLAIM IN ITS OWN NAME. The failure this file keeps
// finding in itself is not a check that is wrong -- it is a check that is
// WEAKER than its name, which reads as the stronger claim in a green run and
// costs nothing until the day the stronger claim is false. A count of segments
// under a name about speech; a whole-call capture total under a name about the
// stretch after a handover; a set comparison under a name about a particular
// half; a distinct-key count that a set of `undefined` satisfies; a search of
// the last 300 events under a name about the room.
//
// AND WHEN THE SUBJECT OF A CLAIM IS NOT OBSERVABLE, THE CLAIM GOES. Two checks
// here asked when a device LEFT the call, and nothing in this stack witnesses
// that moment: the membership state is one writer's view and the product means
// it to be, a half arrives after an unbounded drain, and the harness's click is
// a request. Each rewrite kept the claim and reached for a different proxy, and
// each proxy had its own defeating sequence -- which is the tell that the
// problem was never the measurement. They are DELETED, not narrowed, and what
// replaced them is a smaller thing that is actually seen: the device that
// stayed announcing, in its own log, that it took the recording over. A name
// narrowed onto a claim the evidence still does not reach is the same fault in
// quieter language.
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
/// ASSERTED, not printed. These were computed into a log line and left there,
/// which meant the file stated the premise every other check rests on and never
/// asked it: a run whose second wav held the wrong speech, or a Chrome feeding
/// one profile's audio to both, produced two halves nobody could tell apart and
/// passed everything. [differentFixturesVerdict] is where they are spent now,
/// and [fixtureMatchesDeviceVerdict] is what turns them into a statement about
/// which BROWSER wrote which half.
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
/// Long enough for the survivor's own fixture to be transcribed, which is what
/// puts words in BOTH halves and is the whole reason the handover is driven.
///
/// NOT a bound any check is written on. `PcmChunker` targets 45 seconds, so a
/// tail this length is ONE chunk and its segments cannot say how much of the
/// tail was recorded -- a check that read them as "the rest of the call" is
/// gone rather than reworded. See the note in [3].
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

/// Refuses two devices pointed at the SAME BYTES.
///
/// Two microphones playing one file write two halves nobody can tell apart --
/// which is the exact shape of the merge failure this file exists to catch, so
/// every check would pass hardest at the moment the feature was most broken.
/// A refusal rather than a check, on the terms `browser.js` refuses a missing
/// wav: it is a fact about the rig, and naming the app for it would be a lie.
///
/// WHAT IT CANNOT SEE, and the name is narrowed to say so. It compares two
/// files byte for byte, which is not the same question as whether the two
/// devices SAY different things: a second wav of different bytes carrying the
/// same sentences, a wav of the wrong speech entirely, or a Chrome that fed one
/// profile's audio to both, all pass it. That question can only be asked of the
/// transcript the run produces, and [differentFixturesVerdict] is where it is.
function refuseIfTheDevicesShareAWav() {
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

/// How many pages of history the search below will walk before giving up.
///
/// A ceiling on the WORK, never on the claim: running into it is reported as a
/// search that did not finish, which fails the check that uses it. The normal
/// case costs one page -- a fresh key's own event is at the live end of the
/// room -- and only a key an old call already used walks back at all, which is
/// the case worth paying for.
const KEY_SEARCH_PAGES = 20;
const KEY_SEARCH_PAGE = 500;

/// Halves already in the room under [callKey], written before [before].
///
/// Asked of the room's history rather than of this run, because the thing it
/// is looking for is a call key an EARLIER call already used -- and an earlier
/// call may be one nobody here placed.
///
/// SEARCHED BACK TO THE KEY'S OWN EVENT, and that boundary is what makes the
/// answer a NO rather than a not-here. This read the last 300 events and
/// reported "no earlier half" from it, which is a different sentence: a reuse
/// older than 300 events is invisible to it, and the two answers read alike
/// until the day they differ. They differ for real -- the call-key reuse this
/// guards is a confirmed bug, not a hypothetical.
///
/// The boundary is knowable because a call key IS an event id: the caller's own
/// membership event. Nothing can have been written under a key before the event
/// that IS the key, so history older than that event cannot hold a half under
/// it, and a search that has walked back past its timestamp has covered
/// everything there is to cover.
///
/// Returns whether it FINISHED as well as what it found. A search that ran out
/// of pages, or one whose key the room cannot produce, has not established
/// there was no earlier half -- it has established nothing, and [freshCallKey]
/// treats it that way.
async function halvesUnder(token, callKey, before) {
  const anchor = await mx.eventById(token, ROOM_ID, callKey);
  const anchorTs = typeof anchor?.origin_server_ts === 'number'
    ? anchor.origin_server_ts
    : null;
  if (anchorTs === null) {
    return {
      covered: false,
      halves: [],
      scanned: 0,
      why: `the room has no event ${callKey}, so the moment the call this key `
        + 'names began is unknown and there is no boundary to search back to',
    };
  }
  const halves = [];
  let from = null;
  let scanned = 0;
  for (let page = 0; page < KEY_SEARCH_PAGES; page++) {
    const { chunk, end } = await mx.messagesBack(token, ROOM_ID, {
      from,
      limit: KEY_SEARCH_PAGE,
    });
    scanned += chunk.length;
    for (const e of chunk) {
      if (e.type === TRANSCRIPT
        && e.content?.call_key === callKey
        && (e.origin_server_ts || 0) < before) halves.push(e);
    }
    // The start of the room is a complete answer, and so is having walked back
    // past the key's own event.
    if (!chunk.length || !end) return { covered: true, halves, scanned, why: '' };
    const oldest = Math.min(...chunk.map((e) => e.origin_server_ts || 0));
    if (oldest <= anchorTs) return { covered: true, halves, scanned, why: '' };
    from = end;
  }
  return {
    covered: false,
    halves,
    scanned,
    why: `${scanned} events searched over ${KEY_SEARCH_PAGES} pages without `
      + `reaching ${new Date(anchorTs).toISOString()}, when the call this key `
      + 'names began. Everything between that moment and where the search '
      + 'stopped is unread, so an earlier half under this key would not have '
      + 'been seen',
  };
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

/// Whether both of the account's halves carry READABLE SPEECH.
///
/// The state the handover exists to reach. Without it the drawn-turn count
/// cannot tell a merge from a reader that dropped the empty half, so a run that
/// does not reach it has not tested what it says it tests.
///
/// COUNTED IN WORDS RATHER THAN IN SEGMENTS, and the difference is the whole of
/// it. A segment is a container: a device that opened a recorder, captured
/// silence and published one entry of empty text has a segment and has
/// transcribed nothing. Under the segment count that half read as a device that
/// SPOKE -- the merge log still says `devices 2`, the turn count still sees a
/// timestamp, and the run goes green having never reached the two-speaking-halves
/// state this check is named for. The same measure `halvesWithWords` uses, so
/// the two cannot disagree about what a half carrying speech is.
const bothDevicesSpoke = (halves) =>
  halves.length === 2
  && halves.every((e) => words(spoken(e)).size > 0);

/// Which of the two FIXTURES a set of words came from.
///
/// The two lists are disjoint by construction and each belongs to exactly one
/// wav, so this is the whole of what makes a half's words traceable to a
/// MICROPHONE.
const fixtureIn = (wordSet) => ({
  one: DEVICE_ONE_SAYS.filter((w) => wordSet.has(w)),
  two: DEVICE_TWO_SAYS.filter((w) => wordSet.has(w)),
});

/// Whether the two halves carry the two DIFFERENT fixtures, one each.
///
/// THE PREMISE THE WHOLE MERGE RESTS ON, and for a long time it was only
/// PRINTED. [refuseIfTheDevicesShareAWav] compares the two wavs BYTE for
/// byte, which catches one fixture pointed at twice and nothing else: a second
/// wav of different bytes carrying the same sentences, a wav of the wrong
/// speech, or a Chrome that fed one profile's audio to both, all walk past it.
/// And then two halves nobody can tell apart pass every check in this file --
/// the exact shape of the bug it exists to catch, passing hardest at the moment
/// the feature is most broken.
///
/// So the OUTCOME is asked rather than the rig. Each half must carry words from
/// ONE fixture and none from the other, and the two halves must not carry the
/// same one.
///
/// "NONE OF THE OTHER'S" is a demand a healthy run meets rather than a
/// strictness this invents. Capture taps the track this device PUBLISHES --
/// `call_capture.dart` says so in as many words -- so a half holds its own
/// microphone and nothing else. It is the same property the peer-crossing check
/// at the end of the file already rests on, asked one layer in.
function differentFixturesVerdict(halves) {
  if (halves.length !== 2) {
    return {
      ok: false,
      why: `${halves.length} half/halves from the learner, not 2 -- there is `
        + 'no pair to tell apart',
    };
  }
  const read = halves.map((e) => {
    const w = words(spoken(e));
    return {
      device: e.content?.device_id ?? '<none>',
      size: w.size,
      ...fixtureIn(w),
    };
  });
  const say = (r) => `${r.device} (${r.size} word(s)) carries `
    + `${JSON.stringify(r.one)} of fixture one and ${JSON.stringify(r.two)} of `
    + 'fixture two';
  const both = read.filter((r) => r.one.length > 0 && r.two.length > 0);
  if (both.length) {
    return {
      ok: false,
      why: `${both.map(say).join('; ')} -- one half carries BOTH fixtures, so `
        + 'the two microphones are not separate: either both devices are '
        + "playing the same audio, or one browser's capture reached the other's "
        + 'half',
    };
  }
  // TWO DIFFERENT FINDINGS, and they want different fixes. A half with no words
  // at all is a device that recorded nothing, which the check above already
  // says in red; a half with words but none of either fixture's is a microphone
  // that played something this file does not recognise.
  const wordless = read.filter((r) => r.size === 0);
  if (wordless.length) {
    return {
      ok: false,
      why: `${wordless.map((r) => r.device).join(', ')} carried no words at `
        + 'all, so which fixture it played cannot be asked of it -- the check '
        + 'that both devices transcribed a stretch of the call is the one that '
        + 'names that failure',
    };
  }
  const silent = read.filter((r) => r.one.length === 0 && r.two.length === 0);
  if (silent.length) {
    return {
      ok: false,
      why: `${silent.map(say).join('; ')} -- words, but not one of EITHER `
        + "fixture's, so what that microphone played is not what this file's "
        + 'word lists describe. The lists move with the wavs: replace a fixture '
        + 'and DEVICE_ONE_SAYS/DEVICE_TWO_SAYS move with it, or a run passes on '
        + 'a transcript of different audio',
    };
  }
  const one = read.filter((r) => r.one.length > 0);
  const two = read.filter((r) => r.two.length > 0);
  if (one.length !== 1 || two.length !== 1) {
    return {
      ok: false,
      why: `${read.map(say).join('; ')} -- both halves carry the SAME fixture, `
        + 'so the two devices said the same thing and a reader that kept one of '
        + 'them draws the screen a reader that merged both draws',
    };
  }
  return { ok: true, why: '', one: one[0], two: two[0] };
}

/// Whether each half carries the fixture the BROWSER that is that device played.
///
/// [differentFixturesVerdict] says the two halves hold two different voices; it
/// cannot say which browser's voice is in which half, because a fixture is a
/// fact about a Chrome profile and a half names a MATRIX DEVICE. [deviceOfPage]
/// is what joins the two, and this is the check that spends it: the half naming
/// the device browser one authenticates as has to carry the wav browser one was
/// started with.
///
/// It is the strongest statement of attribution the rig can make. A half is
/// written by the device whose microphone it holds, so a half that names the
/// OTHER device is a half attributed to a device that did not write it -- and
/// two halves swapped over satisfy every check that only counts distinct ids.
///
/// The pairing missing is a FAILURE and not an abstention: without it the file
/// knows the halves carry different fixtures and nothing at all about which
/// device played which, which is the weaker sentence this exists to stop
/// standing in for the stronger one.
function fixtureMatchesDeviceVerdict(fixtures, deviceIds) {
  if (!fixtures.ok) {
    return {
      ok: false,
      why: `the two halves do not carry two different fixtures at all: ${fixtures.why}`,
    };
  }
  if (!deviceIds.one || !deviceIds.two) {
    return {
      ok: false,
      why: 'no half can be tied to a BROWSER: the harness paired device one '
        + `with ${JSON.stringify(deviceIds.one)} and device two with `
        + `${JSON.stringify(deviceIds.two)}, and that pairing -- asked of the `
        + "homeserver with each page's own token -- is the only thing that says "
        + 'which Matrix device a Chrome profile is. Without it the halves are '
        + 'known to carry different fixtures and nothing says which device '
        + 'played which',
    };
  }
  const ok = fixtures.one.device === deviceIds.one
    && fixtures.two.device === deviceIds.two;
  return {
    ok,
    why: ok
      ? ''
      : `the half naming ${fixtures.one.device} carries the fixture browser ONE `
        + `plays, and browser one is device ${deviceIds.one}; the half naming `
        + `${fixtures.two.device} carries browser TWO's, and browser two is `
        + `device ${deviceIds.two}. A half holds the microphone of the device `
        + 'that wrote it, so a half whose words came from the other browser is '
        + 'a half attributed to a device that did not write it',
  };
}

/// Whether the peer's fixture reached its own half, and stayed out of the
/// learner's.
///
/// THE DETECTOR HAS TO BE VALIDATED BEFORE IT MEANS ANYTHING, and it was not.
/// [PEER_SAYS] is a list of words this file EXPECTS the peer to say, and the
/// crossing test looks for them under the LEARNER. If the peer's wav changed,
/// or speech-to-text missed those sentinels while catching other words, the
/// list matches nothing the peer actually said -- and a product that then put
/// the peer's REAL words under the learner leaves the list empty and the check
/// passes, having searched for words nobody spoke.
///
/// `peerWords.size > 0` does not close that hole. The peer having said
/// SOMETHING is not the peer having said the words the test is written on, and
/// only the second makes the search capable of finding anything. So the peer's
/// own half is asked for the sentinels FIRST, and the crossing is then looked
/// for among the ones it actually carries -- the same fixture verification the
/// two learner devices get, applied to the third microphone.
///
/// It is still a detector for a WHOLESALE crossing rather than a partial one: a
/// merge that reached across accounts puts the peer's half under the learner
/// entire, so any sentinel the peer's half carries would arrive with it. A
/// crossing of some turns and not others could miss the ones carrying these
/// words, and no reading of the words alone can close that.
function peerCrossingVerdict(theirs, mine) {
  const peerWords = new Set(theirs.flatMap((e) => [...words(spoken(e))]));
  const heard = PEER_SAYS.filter((w) => peerWords.has(w));
  const crossed = heard.filter((w) => mine.has(w));
  if (mine.size === 0) {
    return {
      ok: false,
      why: 'the learner\'s halves carry no words at all, so nothing of the '
        + 'peer\'s could be found in them however badly the merge went',
    };
  }
  if (peerWords.size === 0) {
    return {
      ok: false,
      why: 'the peer\'s half came back with no words at all -- which is what a '
        + 'peer that never drained produces -- so there is nothing of the '
        + 'peer\'s to look for',
    };
  }
  if (heard.length === 0) {
    return {
      ok: false,
      why: `the peer's half carries ${peerWords.size} word(s) and not one of `
        + `${JSON.stringify(PEER_SAYS)}, so this test is written on words the `
        + 'peer did not say. It would report a crossing ruled out while a '
        + "merge that put the peer's actual words under the learner went "
        + 'unnoticed. Point CALL_CALLEE_WAV at the fixture PEER_SAYS describes, '
        + 'or move PEER_SAYS to the wav',
    };
  }
  return {
    ok: crossed.length === 0,
    heard,
    why: crossed.length
      ? `the learner's halves carry ${crossed.join(' ')} -- words the peer's own `
        + 'half carries too, so the merge crossed ACCOUNTS rather than devices'
      : '',
  };
}

/// THE APP'S OWN STATEMENT THAT THIS DEVICE TOOK THE RECORDING OVER.
///
/// WHY A LOG LINE AND NOT THE SERVER, which is the question two rounds of this
/// file got wrong. There is no observable here for the MOMENT a device left the
/// call. The call membership state is one event per ACCOUNT written by whichever
/// device wrote last, from its own view of the roster -- so a device's ABSENCE
/// from it is one writer's opinion and never a departure ([joinedDevices]
/// measures it lying). A transcript half arrives after an unbounded drain. The
/// harness's own click is a request, not a leave. Each of those was tried here
/// as a stand-in for the instant, and each has a sequence that defeats it.
///
/// So the instant is given up on and the EVENT is asked for instead, of the one
/// party that observes it directly. `ActiveCall` logs this line when the
/// election flips THIS device into recording -- and only then: the write is
/// guarded on the state actually changing, and `_capturing` is read back off
/// the recorder (`capture.isRecording`) before the line is printed, so it
/// states what happened rather than what was wanted. A device logs it when its
/// sibling stops being the recorder, which is the handover, seen by the device
/// the handover is FOR.
///
/// [STOOD_ASIDE] is its opposite number and is what the survivor says at the
/// join, when the other device holds the recording. It is not read as a check;
/// it is printed with the failure so a run that never handed over can be told
/// from one that never elected at all.
const TOOK_OVER = 'Recording this call on this device';
const STOOD_ASIDE = 'Another device of this account is recording this call';

/// Whether a page said it took the recording over AFTER [from].
///
/// SCOPED BY POSITION IN THE PAGE'S OWN OUTPUT, not by a clock. The device that
/// holds the recording at the join says [TOOK_OVER] then too, so an unscoped
/// search answers about the wrong moment; the caller marks the log's length
/// before it clicks, and only what the page said afterwards counts.
const tookOverRecording = (lines, from = 0) =>
  lines.slice(from).some((l) => l.includes(TOOK_OVER));

/// What a page said about the recording, for a failure message.
const recordingLinesIn = (lines, from = 0) =>
  lines.slice(from).filter(
    (l) => l.includes(TOOK_OVER) || l.includes(STOOD_ASIDE) || l.includes('Recording paused'),
  );

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

/// Whether each browser SENT the half that names the device that browser IS.
///
/// SET EQUALITY PROVES NO ATTRIBUTION, and set equality is what stood here.
/// Observed {D1,D2} against derived {D1,D2} passes whether or not browser D1
/// sent the half naming D1: a build that swapped the two device ids over --
/// a worse bug than the one this file exists to catch, because every half then
/// names a device that did not write it -- satisfies it exactly. The per-page
/// wire observation was built to say WHICH browser made which send, and
/// comparing the two as sets throws that away.
///
/// So it is asked per browser, and it takes three observables to answer: the
/// transaction id THIS page was seen PUTting, the arrived half the app's own
/// formula derives that id from, and the device id that half carries -- checked
/// against the device the homeserver says this page's token belongs to. A side
/// passes only when all three name one device.
///
/// THE PAIRING IS REQUIRED, and its absence is a failure rather than a skip:
/// without the third term there is no attribution to be had, and "two valid
/// device ids exist somewhere" is precisely the sentence this replaced.
function sendAttributionVerdict({ sent, devices, halves }) {
  for (const side of ['one', 'two']) {
    const ids = sent[side] || [];
    if (ids.length !== 1) {
      return {
        ok: false,
        why: `browser ${side} was seen sending under ${ids.length} distinct `
          + `transaction id(s) ${JSON.stringify(ids)}, and tying a send to a `
          + 'half needs exactly one',
      };
    }
    if (!devices[side]) {
      return {
        ok: false,
        why: `the harness could not pair browser ${side} with a Matrix device `
          + `(one ${JSON.stringify(devices.one)}, two `
          + `${JSON.stringify(devices.two)}), so there is nothing to check the `
          + 'half it sent AGAINST. The pairing is asked of the homeserver with '
          + "the page's own token (see [deviceOfPage]); without it this run can "
          + 'say two device ids exist and not that either half names its own '
          + 'writer',
      };
    }
  }
  const matched = {};
  for (const side of ['one', 'two']) {
    const id = sent[side][0];
    const half = halves.find((e) => txnIdOf(e) === id);
    if (!half) {
      return {
        ok: false,
        why: `browser ${side} was seen sending under ${JSON.stringify(id)} and `
          + 'no half that arrived derives that id '
          + `(${JSON.stringify(halves.map(txnIdOf))}) -- so the send this page `
          + 'made is not among the halves in the room',
      };
    }
    if (half.content?.device_id !== devices[side]) {
      return {
        ok: false,
        why: `browser ${side} IS device ${JSON.stringify(devices[side])}, and `
          + 'the half it was seen sending names '
          + `${JSON.stringify(half.content?.device_id)} -- a half attributed to `
          + 'a device that did not write it',
      };
    }
    matched[side] = half;
  }
  if (matched.one.event_id === matched.two.event_id) {
    return {
      ok: false,
      why: `both browsers' sends resolve to the one event `
        + `${matched.one.event_id}, so only one half is accounted for`,
    };
  }
  return { ok: true, why: '' };
}

/// Whether this call's key is one no earlier call already wrote a half under.
///
/// THREE things have to hold, and only one of them is about what was found.
///
/// A key that could NOT BE READ is not a fresh key. `reusedKey` is only ever
/// set when there was a key to look an earlier call up by, so `reusedKey ===
/// null` on its own reads a ring whose key never arrived as a clean call -- and
/// a build emitting no call key at all would walk straight past the one check
/// standing between it and a call whose whole transcript the homeserver
/// silently discards.
///
/// And a SEARCH THAT DID NOT FINISH is not a clean call either. [halvesUnder]
/// walks the room back to the key's own event; when it runs out of pages, or
/// cannot find the event that IS the key, it has read part of the history and
/// proved nothing about the rest. "No earlier half in what I read" is not "no
/// earlier half", and the difference is exactly the reuse this exists to catch.
const freshCallKey = (callKey, reused, searched) =>
  typeof callKey === 'string' && callKey.length > 0
  && searched === true
  && reused === null;

/// Whether every half belongs to THE call this run placed.
///
/// Counting distinct keys is a different sentence from this one.
/// `new Set(...).size === 1` is satisfied by a set holding `undefined` -- every
/// half missing its key entirely -- and by any single key at all, including one
/// a different call wrote. So the key is compared against the one the RING
/// carried, which is knowable from the moment the call starts and is what
/// everything else in the file is already scoped to.
const oneCallKeyAcross = (halves, callKey) =>
  halves.length > 0
  && typeof callKey === 'string' && callKey.length > 0
  && halves.every((e) => e.content?.call_key === callKey);

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
  refuseIfTheDevicesShareAWav();
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
  // Printed rather than checked HERE, because the pairing is a fact about the
  // rig and this is the wrong place to judge it: the checks that spend it are
  // where its absence is a finding, and they say so themselves in red rather
  // than standing aside. Two of them cannot be asked at all without it -- the
  // half each browser SENT naming that browser's own device, and each half
  // carrying the fixture its own browser played -- because both need a third
  // term joining a Chrome profile to a Matrix device, and nothing else in the
  // run can supply it. The handover pick uses it too, and there the fallback is
  // CALL_HANDOVER_DEVICE.
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
  let keySearch = { covered: false, halves: [], scanned: 0,
    why: 'no attempt got as far as looking' };
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
    //
    // The search's OWN RESULT is carried out of the loop beside what it found.
    // It walks the room back to the key's own event and can run out of pages;
    // an unfinished search has not learned that no earlier half exists, and
    // [freshCallKey] refuses it rather than reading it as a clean call.
    const earlier = callKey
      ? await halvesUnder(A1.token, callKey, ring?.origin_server_ts ?? 0)
      : { covered: false, halves: [], scanned: 0,
        why: 'the ring carried no call key, so there was nothing to search by' };
    keySearch = earlier;
    if (earlier.halves.length) {
      reusedKey = { callKey, earlier: earlier.halves.length, attempt };
    }
    if (inCall.length >= 2 && earlier.covered && !earlier.halves.length) break;

    console.log(`   (attempt ${attempt}: ${inCall.length} of the learner's ` +
      `devices got in${earlier.halves.length ? ', and the call key was already used' : ''}` +
      `${earlier.covered ? '' : ', and the call-key search did not finish'}` +
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

  // AFTER THIS RING, which is as far as the membership state can be scoped.
  // `com.famedly.call.member` carries no call key for its entries, so nothing
  // here ties a device's membership to the call the ring placed -- only to the
  // window after it, which the teardown-and-settle between attempts is what
  // keeps clean. "The ONE call" is proved further down instead, where every
  // half is required to carry the RING'S own key.
  h.check(s, 'BOTH of the learner devices joined a call after this ring',
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
  //
  // AND A RING WITH NO KEY ON IT FAILS THE SAME CHECK. The lookup above is
  // conditional -- there is nothing to look an earlier call up BY without a key
  // -- so for as long as the check read `reusedKey === null` a build that
  // emitted no call key passed it by never being asked. That is the check
  // passing hardest at the moment it is least able to speak, and it is the one
  // shape this file refuses.
  //
  // AND SO DOES A SEARCH THAT DID NOT FINISH. This used to read the last 300
  // events, which answers "no earlier half in the last 300 events" and was
  // named for "no earlier call already wrote under this key" -- a reuse older
  // than the window is invisible to it, and this is the check standing between
  // the run and a confirmed bug, so the gap is load-bearing. [halvesUnder] now
  // walks back to the key's OWN event, which is the point before which no half
  // under that key can exist, and says whether it got there. See
  // [freshCallKey].
  h.check(s, 'this call has a call key no earlier call already wrote under',
    freshCallKey(callKey, reusedKey, keySearch.covered),
    reusedKey
      ? `attempt ${reusedKey.attempt} rang with call key ${reusedKey.callKey}, ` +
        `which ${reusedKey.earlier} earlier half/halves in this room already ` +
        'carry. Every writer in that call computes the transaction id it ' +
        'already used, the homeserver hands back the earlier event, and the ' +
        'whole of that call\'s transcript is lost with nothing logged'
      : !callKey
        ? `the ring carried no call key (${JSON.stringify(callKey)}), so this ` +
          'was never asked at all: the room was never searched for an earlier ' +
          'call under this key, and nothing below can be scoped to this call ' +
          'either -- the halves\' keys, the reader\'s log line and the ' +
          'transaction ids all name it. A ring whose `m.relates_to` carries ' +
          'no event id is the finding'
        : `the search for an earlier half under ${callKey} did not finish: ` +
          `${keySearch.why}. It found none in what it read, which is not the ` +
          'same answer as there being none -- and this check is what stands ' +
          'between the run and a call whose whole transcript the homeserver ' +
          'discards');

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

  // AND THIS IS WHERE THE HANDOVER IS ASKED ABOUT -- OF THE DEVICE THAT STAYED,
  // AND NOT OF THE SERVER.
  //
  // TWO CHECKS USED TO STAND HERE and neither could prove its name, for one
  // reason: THERE IS NO OBSERVABLE IN THIS STACK FOR THE MOMENT A DEVICE LEFT.
  //
  //   - The call membership state is one event per ACCOUNT, written by whichever
  //     device wrote last, holding that writer's view of the roster. A device's
  //     absence from it is an opinion, not a departure -- [joinedDevices] above
  //     measures the state doing exactly that, and the product means it to.
  //     So "the leaver is gone from the live set" is satisfied by a state that
  //     was already wrong before the click, and "a new membership event was
  //     written" is satisfied by the survivor refreshing its own entry.
  //   - A transcript half arrives after a drain of no fixed length, so its
  //     arrival cannot date the leave it followed.
  //   - The harness's own click is a REQUEST. It is not the leave, and a click
  //     that missed looks exactly like one that worked.
  //
  // Each of those was tried as a stand-in for the instant, in successive
  // rewrites, and each has a sequence that defeats it. The mistake was not the
  // choice of stand-in: it was keeping a claim whose SUBJECT nothing here can
  // witness and going looking for a better proxy for it. So the claim changed.
  //
  // WHAT IS WITNESSED is what the surviving device SAYS about the recording.
  // `ActiveCall` logs [TOOK_OVER] when the election flips it into recording,
  // guarded on the state changing and printed after reading the recorder back --
  // so the device that stayed announces the takeover itself, from the roster it
  // can see, and no state read of the harness's stands between. That is the
  // event the handover exists to cause, and it is the only part of it this run
  // can prove. The hangup is retried against it rather than against a server
  // observable, for the same reason.
  //
  // WHAT IS NOT PROVED, said plainly rather than folded into a name: that the
  // leaver left at any particular moment, and that the survivor recorded ALL of
  // the tail rather than some of it. The 45-second chunker means a 40-second
  // tail is one chunk, so segment positions cannot separate two seconds of
  // recording from forty. What catches a survivor that recorded nothing is not
  // this check but the three below it -- both halves carrying words, each
  // carrying its own fixture, and the reader assembling from two devices.
  const survivorName = leaverName === 'two' ? 'one' : 'two';
  const survivorLog = leaverName === 'two' ? logA1 : logA2;
  // The page's own output up to this point. What the check looks for has to be
  // a line THIS hangup produced: the device holding the recording says the same
  // sentence at the join, and an unscoped search answers about that instead.
  const saidBefore = survivorLog.length;
  const handed = await h.actUntil(
    `device ${leaverName} leaves and device ${survivorName} takes the recording over`,
    () => ui.clickPanel(leaver.page, 'hangup').then(() => {}, () => {}),
    async () => tookOverRecording(survivorLog, saidBefore),
    { tries: 4, gap: 3000 },
  );
  // A DIAGNOSTIC and deliberately not a check. The live set is the state this
  // whole block stopped asking, and printing it keeps it available to whoever
  // reads a failure without letting it stand for anything.
  const stillIn = await mx.liveMembershipDevices(A1.token, ROOM_ID, LEARNER);
  console.log(`   (the live membership now reads ${JSON.stringify(stillIn)} -- ` +
    'a state that under-reports, printed rather than checked)');
  h.check(s, 'the device that stayed says it took the recording over', handed,
    `device ${survivorName} (${deviceIds[survivorName] || 'unidentified'}) never ` +
      `said "${TOOK_OVER}" after device ${leaverName} was told to hang up. What ` +
      `it did say about the recording: ${JSON.stringify(recordingLinesIn(survivorLog, saidBefore))}. ` +
      'Either the hangup never took, or the election did not re-run, or it ran ' +
      'and left the recording where it was. The recorder is the lower of ' +
      `${JSON.stringify([...inCall].sort())}, which is ${predicted}` +
      (paired
        ? `, and device ${leaverName} is ${leaverDevice} -- so the device told ` +
          'to leave was the one holding it'
        : ', and neither browser could be paired with a device id, so the ' +
          'leaver was a guess: set CALL_HANDOVER_DEVICE to the other one and ' +
          'run again') +
      '. NOTE the one local condition that could explain it: this stack\'s ' +
      'LiveKit token lacks CanUpdateOwnMetadata, and the app says so itself -- ' +
      '"the recorder election is running without its capability layer" is in ' +
      'the log written below on every run here');

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
  // NAMED FOR WHAT IT COUNTS. `written.length >= 3` is "three or more halves
  // arrived", and it is not the same sentence as "the three this call should
  // produce arrived": three halves from three learner devices satisfy it. The
  // composition is proved by the two checks below, which is where it belongs --
  // this one is the WAIT'S own result and is named as that.
  h.check(s, 'three or more halves reached the room before the wait ran out',
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
  //
  // COMPARED AGAINST THE RING'S KEY, not merely counted. One distinct key is
  // not the same claim as the right key: a set of size one is satisfied by
  // `{undefined}` -- every half arriving with no key on it, which is a build
  // whose halves the reader cannot group at all -- and by any single key,
  // including one an entirely different call wrote. See [oneCallKeyAcross].
  const keys = new Set(written.map((e) => e.content?.call_key));
  h.check(s, 'every half belongs to the call this run placed',
    oneCallKeyAcross(written, callKey),
    `${written.length} half/halves carrying call key(s) ` +
      `${JSON.stringify([...keys])}; the ring for this call carried ` +
      `${JSON.stringify(callKey)}`);

  // ONE. This is the assertion the whole file is for. Under the keying this
  // replaced there was one half per ACCOUNT, and the second device's speech
  // was destroyed on the way to the screen.
  // COUNTED, and named for the count. "From EACH of its two devices" is a
  // claim about the two halves naming two different devices, and this predicate
  // does not look at a device id at all -- the two checks below are where that
  // is established, and the fixture checks in [6] are where each half is tied
  // to the browser whose microphone it holds.
  h.check(s, 'the account wrote TWO halves, not one',
    mine.length === 2,
    `${mine.length} half/halves from the learner, not 2` +
      (mine.length
        ? ` (devices ${mine.map((e) => JSON.stringify(e.content?.device_id)).join(', ')})`
        : ''));

  const ids = mine.map((e) => e.content?.device_id);
  const named = ids.filter((d) => typeof d === 'string' && d.length > 0);
  // A DEVICE, and not yet the device that WROTE it. All this reads is that the
  // field is present and usable; whether the name is the writer's is a
  // different question with different observables, and it is asked twice below
  // -- once off the wire, against the transaction id each browser was seen
  // sending, and once off the audio, against the fixture each browser plays.
  h.check(s, 'each half NAMES a device',
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

  h.check(s, 'the two transcript sends carried DIFFERENT transaction ids',
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
  h.check(s, 'the ids sent are the same SET the formula derives from the events',
    idsSentMatchDerived(observed, txns),
    `sent ${JSON.stringify(observed)}; derived from the events that arrived ` +
      `${JSON.stringify([...txns].sort())}. They have to be the same set: if ` +
      'they are not, either a half arrived from a device that sent under a ' +
      'different key, or this file\'s copy of the formula has fallen behind ' +
      'the app\'s');

  // AND WHICH BROWSER SENT WHICH HALF, which the set above cannot say.
  //
  // Two sets that match prove two valid device ids exist at both ends of the
  // comparison and nothing about their ARRANGEMENT: browser one sending the
  // half that names device two, and browser two sending the half that names
  // device one, satisfies it exactly -- and that is a worse bug than the one
  // this file exists to catch, because then every half on the screen is
  // attributed to a device that did not write it.
  //
  // The wire observation was built to answer this and the set comparison threw
  // the answer away. Asked per browser now: the id THIS page was seen PUTting,
  // the half the formula derives it from, and that half's device id against the
  // device the homeserver says this page's own token is. See
  // [sendAttributionVerdict].
  const attribution = sendAttributionVerdict({
    sent: sentIds,
    devices: deviceIds,
    halves: mine,
  });
  h.check(s, 'the half each browser SENT names that browser\'s own device',
    attribution.ok, attribution.why);

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

  // NOTHING HERE ASKS THE SURVIVOR'S HALF WHEN IT RECORDED, and the absence is
  // deliberate. A check stood here that read `chunks_captured > 0` -- a
  // whole-call total a device accumulates even while standing aside, since a
  // non-recorder captures and discards -- and then one that required a segment
  // positioned after the harness's own click. Neither proved "the rest of the
  // call": the first is not about the tail at all, and the second is satisfied
  // by a chunk that straddles the click, which is audio from before the leave.
  //
  // The tail is 40 seconds and `PcmChunker` targets 45, so the survivor's tail
  // is ONE chunk whose position sits at its start. There is no reading of it
  // that separates a survivor which recorded two seconds from one which
  // recorded forty, and no name for such a check that is not more than the
  // evidence. It is gone rather than reworded.
  //
  // What the survivor's half is still asked, elsewhere and honestly: that it
  // carries words at all (`BOTH of the learner devices transcribed`), that the
  // words are its OWN fixture (`each half carries the fixture its OWN browser
  // played`), and that the reader assembled the account's half from two
  // devices. A survivor that recorded nothing fails all three -- which is how
  // the one real failure a run of this file has found was caught.

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
  // event. ASSERTED below rather than printed: for as long as these two lists
  // were only logged, a run whose second wav held the wrong speech, or a Chrome
  // that fed one profile's audio to both, went green on two halves nobody could
  // tell apart -- the premise the whole merge rests on, unchecked.
  for (const e of mine) {
    const hit = fixtureIn(words(spoken(e)));
    console.log(`   ${e.content?.device_id}: fixture one ` +
      `${JSON.stringify(hit.one)}, fixture two ${JSON.stringify(hit.two)}`);
  }
  const fixtures = differentFixturesVerdict(mine);
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
    `per half: ${mine
      .map((e) => `${e.content?.device_id}=${e.content?.segments?.length ?? 0} ` +
        `segment(s)/${words(spoken(e)).size} word(s)`)
      .join(', ') || 'none'}. COUNTED IN WORDS: a half with a segment carrying ` +
      'no readable text has published a container and transcribed nothing, and ' +
      'it used to pass this. CaptureElection lets only the device holding the ' +
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

  // AND THAT THE TWO DEVICES SAID DIFFERENT THINGS, which is the premise every
  // check above rests on and none of them asks.
  //
  // [refuseIfTheDevicesShareAWav] compares the two wavs BYTE for byte before
  // anything opens, and that catches one fixture pointed at twice and nothing
  // else. A second wav of different bytes carrying the same sentences, a wav of
  // the wrong speech, a Chrome that handed one profile's audio to both -- all
  // pass the refusal, and then two halves nobody can tell apart pass every
  // check in this file, hardest at the moment the feature is most broken.
  h.check(s, 'the two halves carry the two DIFFERENT fixtures',
    fixtures.ok,
    `${fixtures.why}. The two devices play different wavs so that a half from ` +
      'the wrong device and a half from the right one are not the same event; ' +
      'CALL_LEARNER_ONE_WAV and CALL_LEARNER_TWO_WAV are what point at them, ' +
      'and DEVICE_ONE_SAYS/DEVICE_TWO_SAYS are what this file recognises them by');

  // AND WHICH BROWSER PLAYED WHICH, which is the sentence that ties a half to
  // its writer through the audio rather than through the id it carries. A half
  // holds the track its own device published, so the half naming the device
  // browser one authenticates as has to carry browser one's wav -- and two
  // halves swapped over satisfy every check that only counts distinct ids.
  const owned = fixtureMatchesDeviceVerdict(fixtures, deviceIds);
  h.check(s, 'each half carries the fixture its OWN browser played',
    owned.ok, owned.why);

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
    h.skipped(s, 'the panel drew at least as many turns as the halves carry',
      'the panel never opened, so what it drew says nothing -- and the check ' +
        'above says that in red');
  } else {
    // NAMED FOR THE COUNT, because a count is all the screen offers. The words
    // are drawn by CanvasKit and reach neither the page text nor the semantics
    // tree, so "every turn either device wrote is drawn" is not a sentence this
    // can establish: it cannot match a drawn turn to a written one, only their
    // numbers. A reader that keeps one of an account's halves is short by
    // exactly the turns of the half it dropped, and that is what a floor
    // catches.
    h.check(s, 'the panel drew at least as many turns as the halves carry',
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
  // ONE CHECK, and it fails on a detector that cannot detect as well as on a
  // crossing. Splitting the two put "there was nothing to compare" in the SKIP
  // column, where it cost nothing.
  //
  // AND THE DETECTOR IS VALIDATED FIRST. Requiring only that the peer said
  // SOMETHING left the search itself unchecked: PEER_SAYS is what this file
  // expects the peer to say, and if the wav changed or speech-to-text caught
  // different words, the search runs over words nobody spoke and comes back
  // empty for a reason that has nothing to do with the product. The peer's own
  // half now has to carry the sentinels before their absence under the learner
  // is allowed to mean anything. See [peerCrossingVerdict].
  const peerCrossing = peerCrossingVerdict(theirs, allMine);
  h.check(s, "the peer's own fixture words reached its half and NOT the learner's",
    peerCrossing.ok, peerCrossing.why);

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
  halvesUnder,
  KEY_SEARCH_PAGES,
  recorderAmong,
  mergeCountsIn,
  provesTwoDeviceMerge,
  bothDevicesSpoke,
  allHalvesArrived,
  sentUnderDifferentIds,
  idsSentMatchDerived,
  sendAttributionVerdict,
  freshCallKey,
  oneCallKeyAcross,
  fixtureIn,
  differentFixturesVerdict,
  fixtureMatchesDeviceVerdict,
  peerCrossingVerdict,
  tookOverRecording,
  recordingLinesIn,
  countTurns,
  spoken,
  words,
  DEVICE_ONE_SAYS,
  DEVICE_TWO_SAYS,
};
