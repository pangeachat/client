// Every fact in this folder that is about a MACHINE rather than about the
// product.
//
// The scenarios used to carry these inline -- one laptop's Chrome path, one
// laptop's /tmp, one person's phone serial, one local stack's room id. The
// files still read as if they were describing the product, so the next person
// discovered the difference by watching a run fail on a path that does not
// exist on their disk. Everything below reads an environment variable and
// falls back to the local stack the README describes; the one thing that
// cannot have a sensible default -- whose phone -- throws and says what to set.
const fs = require('fs');
const os = require('os');
const path = require('path');

const env = (name, fallback) => process.env[name] || fallback;

// Where the app is served and where its homeserver lives. Both are the local
// stack by default: `spa_server.py build/web 8091` and Synapse on 8008.
const appUrl = env('APP_URL', 'http://localhost:8091');
const homeserver = env('PROBE_HS', 'http://localhost:8008');
const serverName = env('CALL_SERVER_NAME', 'pangea.localhost');

// The fixture room the two test accounts share on the LOCAL stack. It is not
// a magic constant of the product -- it is whatever room your local Synapse
// created when the two accounts first spoke -- so a stack seeded differently
// sets CALL_ROOM and everything follows.
const room = env('CALL_ROOM', '!HgavfyvZrMpYhLFMLt');
const roomId = room.includes(':') ? room : `${room}:${serverName}`;

// Scratch: Chrome profiles, fake-microphone audio, and screenshots. Kept out
// of the repo and off any one person's absolute path; TMPDIR moves the lot.
const workDir = env('CALL_WORK_DIR', path.join(os.tmpdir(), 'callweb'));
const shotsDir = env('CALL_SHOT_DIR', path.join(workDir, 'shots'));

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

/// A path to write a screenshot or a log to. Created on demand, because a
/// screenshot that fails with ENOENT throws away the only evidence of the
/// failure it was taken to explain.
function shot(name) {
  ensureDir(shotsDir);
  return path.join(shotsDir, name);
}

/// A persistent Chrome profile. Persistent on purpose: logging in twice per
/// scenario costs more than every check in the file put together.
function profileDir(name) {
  return path.join(workDir, `${name}-profile`);
}

// The two local-stack test accounts. Passwords in the clear are correct here
// and nowhere else: these exist only on a laptop's Synapse, seeded by the
// local-dev setup, and a run that cannot log in has nothing to test.
const accounts = {
  learner: {
    user: env('CALL_LEARNER_USER', 'learner'),
    pass: env('CALL_LEARNER_PASS', 'learnerpass'),
    profile: profileDir('learner'),
    wav: env('CALL_CALLER_WAV', path.join(workDir, 'caller.wav')),
  },
  calltester: {
    user: env('CALL_CALLTESTER_USER', 'calltester'),
    pass: env('CALL_CALLTESTER_PASS', 'calltesterpass'),
    profile: profileDir('calltester'),
    wav: env('CALL_CALLEE_WAV', path.join(workDir, 'callee.wav')),
  },
};

// TWO DEVICES of the learner account, for `transcript_two_devices.js`.
//
// Every entry above is one account with ONE Chrome profile, so the same user
// could never open twice -- and two devices of one account in one call is
// exactly the case a transcript half used to be destroyed by: keyed by the
// account alone, the two halves were indistinguishable and the reader kept one
// of them.
//
// A Chrome profile is a whole storage partition, so a second one signs in again
// and Synapse mints a SECOND Matrix device for the same credentials. That is
// all a device is here. The port is already a parameter of `openParticipant`,
// so nothing else about the harness has to change.
//
// BOTH are new profiles rather than one new one beside `learner`. The scenario
// needs two long fixtures nothing else uses -- see below -- and reusing the
// `learner` profile would either change what every other scenario's microphone
// plays or have two entries fighting over one profile lock.
//
// A VOICE EACH, and that is not a convenience. Two devices playing the same
// audio write two halves nobody can tell apart, which is the exact shape of a
// merge that quietly kept one of them: the check that matters would pass
// hardest at the moment the feature was most broken.
//
// LONG, and that is not one either. `CaptureElection` lets only ONE of an
// account's devices record at a time, so the only way to get speech into BOTH
// halves is for the recorder to leave mid-call and the other device to take
// over -- and a fixture Chrome has already played to the end (it is told
// `%noloop`) hands the successor silence. Around two minutes, with the same
// eight sentences three times over, so any stretch of the call carries words
// whichever device is holding it.
accounts.learnerFirstDevice = {
  user: accounts.learner.user,
  pass: accounts.learner.pass,
  profile: profileDir('learner-first'),
  wav: env('CALL_LEARNER_ONE_WAV', path.join(workDir, 'learner_one.wav')),
};

// A SECOND DEVICE of the learner account.
//
// Every entry above is one account with ONE Chrome profile, so the same user
// could never open twice -- and two devices of one account in one call is
// exactly the case a transcript half used to lose: keyed by the account alone,
// the two halves were indistinguishable and the reader kept one of them.
//
// A Chrome profile is a whole storage partition, so a second one signs in
// again and Synapse mints a SECOND Matrix device for the same credentials.
// That is all a second device is here. The port is already a parameter of
// `openParticipant`, so nothing else about the harness has to change.
//
// ITS OWN WAV, and that is not a convenience. Two devices playing the same
// audio write two halves nobody can tell apart -- which is the exact shape of
// a merge that quietly kept one of them, so the check that matters would pass
// hardest when the feature was most broken.
accounts.learnerSecondDevice = {
  user: accounts.learner.user,
  pass: accounts.learner.pass,
  profile: profileDir('learner-second'),
  wav: env('CALL_LEARNER_TWO_WAV', path.join(workDir, 'learner_two.wav')),
};

// The browser the harness drives. puppeteer-core ships no browser of its own,
// so this has to be a real install; CHROME points at a different one.
const chrome = env(
  'CHROME',
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
);

/// adb, from the SDK if it is where the SDK usually is, otherwise from PATH.
function findAdb() {
  if (process.env.ADB) return process.env.ADB;
  const roots = [process.env.ANDROID_HOME, process.env.ANDROID_SDK_ROOT,
    path.join(os.homedir(), 'Library/Android/sdk'),
    path.join(os.homedir(), 'Android/Sdk')].filter(Boolean);
  for (const r of roots) {
    const candidate = path.join(r, 'platform-tools', 'adb');
    if (fs.existsSync(candidate)) return candidate;
  }
  return 'adb';
}

const phone = {
  adb: findAdb(),
  // The debug build carries an applicationIdSuffix; the release build does not.
  pkg: env('PHONE_PKG', 'com.talktolearn.chat'),
  /// Whose phone. There is no defensible default: a serial baked in here is
  /// one person's rig, and everybody else's run dies with "device not found"
  /// rather than with the setting they were missing. Read lazily so the
  /// browser-only scenarios, which never touch a phone, do not have to care.
  serial() {
    const s = process.env.PHONE_SERIAL;
    if (!s) {
      throw new Error(
        'set PHONE_SERIAL to the device you are testing on (see `adb devices`), '
        + 'and PHONE_PKG if your build carries an applicationIdSuffix');
    }
    return s;
  },
};

module.exports = {
  appUrl, homeserver, serverName, room, roomId,
  workDir, shotsDir, ensureDir, shot, profileDir,
  accounts, chrome, phone,
};
