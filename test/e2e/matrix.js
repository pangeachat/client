// Assertions come from the SERVER, never from the canvas.
//
// The point of the harness is to compare what the two participants' timelines
// actually contain. Reading that from Matrix means a scenario can be checked
// exactly, and means a UI change cannot quietly stop the check from working.
const HS = require('./config').homeserver;

async function api(path, { token, method = 'GET', body } = {}) {
  const res = await fetch(HS + path, {
    method,
    headers: {
      ...(token ? { authorization: 'Bearer ' + token } : {}),
      'content-type': 'application/json',
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  const text = await res.text();
  let json;
  try {
    json = text ? JSON.parse(text) : {};
  } catch (_) {
    json = { raw: text };
  }
  if (!res.ok) {
    const err = new Error(`${method} ${path} -> ${res.status} ${text.slice(0, 200)}`);
    // The STATUS, alongside the message. A caller that wants to treat one
    // outcome as an answer -- an absent piece of account data is a 404, and a
    // real answer -- must be able to tell it apart from an expired token or a
    // homeserver that is down, and matching on the text of a message is how a
    // catch comes to swallow the failures it was never meant to.
    err.status = res.status;
    throw err;
  }
  return json;
}

async function login(user, password) {
  const r = await api('/_matrix/client/v3/login', {
    method: 'POST',
    body: {
      type: 'm.login.password',
      identifier: { type: 'm.id.user', user },
      password,
    },
  });
  return { token: r.access_token, userId: r.user_id, deviceId: r.device_id };
}

/// Gives a session back.
///
/// Every login creates a DEVICE, and the two fixture accounts are reused
/// forever -- their call membership state already carries an entry from every
/// past session, and `liveMemberships` exists to filter them out. A session
/// taken to ask one question and then abandoned adds to that for nothing.
///
/// Never throws: it is cleanup, and cleanup that can fail a run is worse than
/// the device it was tidying away.
async function logout(token) {
  try {
    await api('/_matrix/client/v3/logout', { token, method: 'POST', body: {} });
  } catch (_) {}
}

/// The room the two accounts share, newest-activity first.
async function directRoomWith(token, peerUserId) {
  const joined = await api('/_matrix/client/v3/joined_rooms', { token });
  for (const roomId of joined.joined_rooms) {
    try {
      const members = await api(
        `/_matrix/client/v3/rooms/${encodeURIComponent(roomId)}/joined_members`,
        { token },
      );
      const ids = Object.keys(members.joined || {});
      if (ids.length === 2 && ids.includes(peerUserId)) return roomId;
    } catch (_) {}
  }
  return null;
}

/// Recent timeline, oldest-first.
async function timeline(token, roomId, limit = 60) {
  const r = await api(
    `/_matrix/client/v3/rooms/${encodeURIComponent(roomId)}/messages?dir=b&limit=${limit}`,
    { token },
  );
  return (r.chunk || []).slice().reverse();
}

/// The name the APP will draw for a user.
///
/// Read from the server rather than guessed from the Matrix id: the screen
/// draws a display name, and a scenario that assumes the localpart is testing
/// its own assumption. The id is the fallback the client itself uses when a
/// profile carries no name.
async function displayName(token, userId) {
  try {
    const p = await api(`/_matrix/client/v3/profile/${encodeURIComponent(userId)}`, { token });
    return (p && p.displayname) || userId;
  } catch (_) {
    return userId;
  }
}

/// The language this account is LEARNING, as the app stores it -- 'en-US',
/// 'hi', or null when the profile has not been filled in.
///
/// Speech-to-text is asked for the SPEAKER'S OWN target language, read off this
/// profile, so an account learning Hindi has its English speech transcribed as
/// Hindi and the provider answers with nothing at all. That is invisible: the
/// call rings, connects, and writes both halves, and only the words are
/// missing -- which reads as a broken capture path rather than as an account
/// pointed at the wrong language.
/// A 404 is the only failure this treats as an answer -- an account that has
/// never filled in a profile genuinely has no target language. Everything else
/// is rethrown: an expired token or a homeserver that is down would otherwise
/// come back as "learning nothing yet" and be reported as a fixture problem.
async function targetLanguage(token, userId) {
  let p;
  try {
    p = await api(
      `/_matrix/client/v3/user/${encodeURIComponent(userId)}/account_data/profile`,
      { token },
    );
  } catch (e) {
    if (e && e.status === 404) return null;
    throw e;
  }
  const code = p && p.user_settings && p.user_settings.target_language;
  return typeof code === 'string' && code ? code : null;
}

/// A language code reduced to the language itself: 'en-US' and 'en' are the
/// same language to a speech provider, and a fixture check that turned on the
/// region would refuse a perfectly good account.
function baseLang(code) {
  return String(code || '').toLowerCase().split(/[-_]/)[0];
}

const CALL = 'pangea.call';
const DECLINE = 'org.matrix.msc4310.rtc.decline';
const RING = 'org.matrix.msc4075.rtc.notification';

/// A call card, reduced to what a person would read off the screen.
function card(ev, viewerId) {
  const c = ev.content || {};
  const caller = typeof c.caller === 'string' ? c.caller : ev.sender;
  const outgoing = caller === viewerId;
  const answered = c.answered === true;
  const declined = c.declined === true;
  const missed = !answered && !declined;
  let label;
  if (declined) label = outgoing ? 'Call declined' : 'You declined this call';
  else if (missed) label = outgoing ? 'No answer' : (c.video === true ? 'Missed video call' : 'Missed call');
  else label = c.video === true ? 'Video call' : 'Voice call';
  return {
    id: ev.event_id,
    ts: ev.origin_server_ts,
    sender: ev.sender,
    caller,
    outgoing,
    answered,
    declined,
    video: c.video === true,
    durationMs: c.duration_ms,
    label,
  };
}

function cardsIn(events, viewerId) {
  // The renderer's first-per-key rule, mirrored: only the FIRST card per
  // call_key in timeline order counts (origin_server_ts, event id as final
  // tie-break). A writer and a survivor racing across the settle window can
  // both post; the product renders one, so the harness counts one. Keyless
  // cards always count, as they always rendered.
  const all = events.filter((e) => e.type === CALL);
  const firstPerKey = new Map();
  for (const e of all) {
    const key = e.content && e.content.call_key;
    if (typeof key !== 'string') continue;
    const cur = firstPerKey.get(key);
    if (!cur) { firstPerKey.set(key, e); continue; }
    const byTime = (cur.origin_server_ts || 0) - (e.origin_server_ts || 0);
    if (byTime > 0 || (byTime === 0 && cur.event_id > e.event_id)) firstPerKey.set(key, e);
  }
  return all
    .filter((e) => {
      const key = e.content && e.content.call_key;
      if (typeof key !== 'string') return true;
      return firstPerKey.get(key) === e;
    })
    .map((e) => card(e, viewerId));
}

function countType(events, type) {
  return events.filter((e) => e.type === type).length;
}

/// How many LIVE call memberships this account has in the room.
///
/// Only non-expired ones count. Every login creates a new device, and a leave
/// only removes the entry for the device doing the leaving, so the state
/// accumulates entries from every past session. Counting them all made a
/// perfectly good hangup look like it had failed -- the stale entries are all
/// long expired, which is exactly how the SDK itself filters them.
async function liveMemberships(token, roomId, userId) {
  try {
    const st = await api(
      `/_matrix/client/v3/rooms/${encodeURIComponent(roomId)}/state/com.famedly.call.member/${encodeURIComponent(userId)}`,
      { token },
    );
    const mems = Array.isArray(st.memberships) ? st.memberships : [];
    const now = Date.now();
    return mems.filter((m) => typeof m.expires_ts === 'number' && m.expires_ts > now).length;
  } catch (_) {
    return 0;
  }
}

async function hasMembership(token, roomId, userId) {
  return (await liveMemberships(token, roomId, userId)) > 0;
}

module.exports = { api, login, logout, displayName, targetLanguage, baseLang, hasMembership, liveMemberships, directRoomWith, timeline, cardsIn, card, countType, CALL, DECLINE, RING, HS };
