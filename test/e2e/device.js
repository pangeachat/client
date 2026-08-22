// A PHONE participant for the E2E harness, driven over adb.
//
// Same philosophy as the browser side: navigation is minimal, clicks are
// proven by SERVER outcomes (membership, decline, upload), and the phone's
// own logs are captured per scenario so a silent failure has evidence.
const { execFile } = require('child_process');
const { promisify } = require('util');
const run = promisify(execFile);
const ADB = process.env.ADB || `${process.env.HOME}/Library/Android/sdk/platform-tools/adb`;
const SERIAL = process.env.PHONE_SERIAL || '56091FDAP001N3';
const PKG = 'com.talktolearn.chat.debug';

async function adb(...args) {
  const { stdout } = await run(ADB, ['-s', SERIAL, ...args], { maxBuffer: 64 * 1024 * 1024 });
  return stdout;
}

async function ensureAwakeAndForeground() {
  await adb('shell', 'input', 'keyevent', 'KEYCODE_WAKEUP');
  await new Promise((r) => setTimeout(r, 800));
  // A fingerprint lock cannot be driven from here, and pretending otherwise
  // cost a run: every later step "failed" when the truth was a lock screen.
  // Detect it and say so.
  const kg = await adb('shell', 'dumpsys', 'window').catch(() => '');
  if (/mDreamingLockscreen=true|isStatusBarKeyguard=true|KeyguardShowing=true/i.test(kg)) {
    throw new Error('the phone is LOCKED (fingerprint) -- ask the user to unlock it');
  }
  await adb('shell', 'monkey', '-p', PKG, '-c', 'android.intent.category.LAUNCHER', '1').catch(() => {});
  await new Promise((r) => setTimeout(r, 2500));
  const front = await adb('shell', 'dumpsys', 'activity', 'activities');
  if (!front.includes(PKG)) throw new Error('app is not foreground on the phone');
}

async function screenshot(path) {
  const { stdout } = await run(ADB, ['-s', SERIAL, 'exec-out', 'screencap', '-p'], { encoding: 'buffer', maxBuffer: 64 * 1024 * 1024 });
  require('fs').writeFileSync(path, stdout);
  return path;
}

/// Taps, after making sure something is actually there to tap.
///
/// The screen sleeping mid-run is indistinguishable, from the server's side,
/// from a product that ignores the answer button: the taps land on a dark
/// panel and nothing happens. Every tap therefore wakes the device first --
/// cheap, and it removes a whole class of phantom failure.
async function tap(x, y) {
  await adb('shell', 'input', 'keyevent', 'KEYCODE_WAKEUP').catch(() => {});
  await adb('shell', 'input', 'tap', String(x), String(y));
}

// Banner control positions on THIS device (960x2142), calibrated from a
// screenshot of a live ring and verified by the server-side outcome each run.
// If the outcome check fails, the scenario screenshots the phone so the
// calibration can be corrected with evidence rather than guesses.
const BANNER = {
  answer: { x: 842, y: 436 },
  decline: { x: 712, y: 436 },
  message: { x: 353, y: 436 },
};

async function logcatClear() { await adb('logcat', '-c'); }
async function logcatDump() { return adb('logcat', '-d', '-v', 'time'); }

module.exports = { adb, ensureAwakeAndForeground, screenshot, tap, BANNER, logcatClear, logcatDump, PKG, SERIAL };
