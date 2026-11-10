// One-time LOCAL setup for the route suite: the en/es and en/fr learner
// accounts, a direct room between each of them and `calltester`, and their
// learning languages. Idempotent. Refuses anything but a local homeserver.
//
//   node test/e2e/routes/setup_local.js
//
// Accounts are registered through Synapse's shared-secret admin registration,
// with the secret read out of the LOCAL container at run time
// (ROUTES_SYNAPSE_CONTAINER, default pangea-synapse-local) -- never stored.
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const R = require('./lib');

const { mx, cfg } = R;
const CONTAINER = process.env.ROUTES_SYNAPSE_CONTAINER || 'pangea-synapse-local';
const DOCKER_CONTEXT = process.env.ROUTES_SYNAPSE_CONTEXT || 'orbstack';

function sharedSecret() {
  const yaml = execFileSync('docker', ['--context', DOCKER_CONTEXT, 'exec', CONTAINER, 'cat', '/data/homeserver.yaml'], { encoding: 'utf8' });
  const m = /^registration_shared_secret:\s*["']?([^"'\n]+)["']?/m.exec(yaml);
  if (!m) throw new Error('no registration_shared_secret in the local homeserver.yaml');
  return m[1];
}

async function register(user, pass) {
  try {
    await mx.login(user, pass);
    console.log(`   ${user}: exists`);
    return;
  } catch (_) { /* register below */ }
  const { nonce } = await mx.api('/_synapse/admin/v1/register');
  const mac = crypto.createHmac('sha1', sharedSecret())
    .update(`${nonce}\0${user}\0${pass}\0notadmin`).digest('hex');
  await mx.api('/_synapse/admin/v1/register', { method: 'POST', body: { nonce, username: user, password: pass, admin: false, mac } });
  console.log(`   ${user}: registered`);
}

async function main() {
  R.refuseIfNotLocal();
  const learner = cfg.accounts.learner;
  const peer = cfg.accounts.calltester;
  const L = await mx.login(learner.user, learner.pass);
  const P = await mx.login(peer.user, peer.pass);
  const template = await mx.api(`/_matrix/client/v3/user/${encodeURIComponent(L.userId)}/account_data/profile`, { token: L.token });
  const out = {};
  for (const [k, a] of Object.entries(R.extra)) {
    await register(a.user, a.pass);
    const S = await mx.login(a.user, a.pass);
    const profile = JSON.parse(JSON.stringify(template));
    profile.user_settings = { ...profile.user_settings, target_language: a.target, source_language: 'en', created_at: new Date().toISOString().slice(0, 23) };
    await mx.api(`/_matrix/client/v3/user/${encodeURIComponent(S.userId)}/account_data/profile`, { token: S.token, method: 'PUT', body: profile });
    await mx.api(`/_matrix/client/v3/profile/${encodeURIComponent(S.userId)}/displayname`, { token: S.token, method: 'PUT', body: { displayname: `Routes ${k.toUpperCase()}` } });
    let roomId = await mx.directRoomWith(S.token, P.userId).catch(() => null);
    if (!roomId) {
      const r = await mx.api('/_matrix/client/v3/createRoom', { token: S.token, method: 'POST', body: { is_direct: true, invite: [P.userId], preset: 'trusted_private_chat', name: undefined } });
      roomId = r.room_id;
      await mx.api(`/_matrix/client/v3/rooms/${encodeURIComponent(roomId)}/join`, { token: P.token, method: 'POST', body: {} });
      for (const [who, other] of [[S, P.userId], [P, S.userId]]) {
        let direct = {};
        try { direct = await mx.api(`/_matrix/client/v3/user/${encodeURIComponent(who.userId)}/account_data/m.direct`, { token: who.token }); } catch (_) {}
        direct[other] = [...new Set([...(direct[other] || []), roomId])];
        await mx.api(`/_matrix/client/v3/user/${encodeURIComponent(who.userId)}/account_data/m.direct`, { token: who.token, method: 'PUT', body: direct });
      }
      await mx.api(`/_matrix/client/v3/rooms/${encodeURIComponent(roomId)}/send/m.room.message/routes-hello-${Date.now()}`,
        { token: S.token, method: 'PUT', body: { msgtype: 'm.text', body: 'route suite room' } });
    }
    out[`${k}_calltester`] = roomId.split(':')[0];
    console.log(`   ${a.user} <-> calltester: ${roomId} (learning ${a.target})`);
    await mx.logout(S.token).catch(() => {});
  }
  fs.mkdirSync(cfg.workDir, { recursive: true });
  fs.writeFileSync(path.join(cfg.workDir, 'routes-rooms.json'), JSON.stringify(out, null, 2));
  await mx.logout(L.token).catch(() => {});
  await mx.logout(P.token).catch(() => {});
  console.log(`rooms -> ${path.join(cfg.workDir, 'routes-rooms.json')}`);
}

main().catch((e) => { console.error('SETUP FAILED', e.message); process.exit(1); });
