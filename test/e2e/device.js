// A PHONE participant for the E2E harness, driven over adb.
//
// Same philosophy as the browser side: navigation is minimal, clicks are
// proven by SERVER outcomes (membership, decline, upload), and the phone's
// own logs are captured per scenario so a silent failure has evidence.
const { execFile } = require('child_process');
const { promisify } = require('util');
const run = promisify(execFile);
// Whose phone, and which build. Both come from config.js, which reads them
// from the environment: a serial and a package baked in here are one person's
// rig, and the next person's run fails with "device not found" rather than
// with the setting they were missing. Reading the serial here rather than
// lazily is deliberate -- only the device scenarios require this file, and
// they should refuse at the top rather than half way through a call.
const cfg = require('./config');
const ADB = cfg.phone.adb;
const PKG = cfg.phone.pkg;
const SERIAL = cfg.phone.serial();

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

// The rest of the controls the scenarios tap, at the same calibration and
// under the same rule: a position is never believed, only the server outcome
// that follows it is. They live here rather than inline in five scenarios
// because they are a fact about a 960x2142 PHONE, not about the product --
// and a number repeated in five files is a number that gets recalibrated in
// four of them.
//
// To recalibrate: run the scenario, open the screenshot it takes just before
// the tap, and read the centre of the control off it. Every one of these was
// derived that way; `returnToCall` in particular was moved once because the
// old point sat on the control's top edge and missed about half the time.
const TAP = {
  // The Return-to-your-call offer, raised after the app is relaunched.
  returnToCall: { x: 784, y: 260 },
  // Hang up on the phone's own in-call panel.
  hangup: { x: 480, y: 1830 },
  // The camera toggle, to the right of Hang up on that same panel.
  camera: { x: 665, y: 1830 },
  // Hang up on the GLOBAL CALL TILE -- the minimised control that is what is
  // actually on screen once the call is behind another route. A different
  // layout entirely from the panel above, which is why guessing between them
  // is how a stray tap once opened the vocabulary drawer.
  tileHangup: { x: 872, y: 233 },
  // The chat list, in the bottom navigation.
  chatList: { x: 371, y: 1984 },
};

/// Taps a NAMED control, from either table. Named rather than numbered so a
/// recalibration happens once and a reader can tell what was aimed at.
async function tapControl(name) {
  const p = TAP[name] || BANNER[name];
  if (!p) throw new Error(`no calibrated position for "${name}"`);
  return tap(p.x, p.y);
}

async function logcatClear() { await adb('logcat', '-c'); }
async function logcatDump() { return adb('logcat', '-d', '-v', 'time'); }

module.exports = { adb, ensureAwakeAndForeground, screenshot, tap, tapControl, BANNER, TAP, logcatClear, logcatDump, PKG, SERIAL };
