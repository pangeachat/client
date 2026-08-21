// Assertions come from the SERVER, never from the canvas.
//
// The point of the harness is to compare what the two participants' timelines
// actually contain. Reading that from Matrix means a scenario can be checked
// exactly, and means a UI change cannot quietly stop the check from working.
const HS = process.env.PROBE_HS || 'http://localhost:8008';

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
    throw new Error(`${method} ${path} -> ${res.status} ${text.slice(0, 200)}`);
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
  return events.filter((e) => e.type === CALL).map((e) => card(e, viewerId));
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

module.exports = { api, login, hasMembership, liveMemberships, directRoomWith, timeline, cardsIn, card, countType, CALL, DECLINE, RING, HS };
