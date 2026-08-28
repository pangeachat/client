// What a control is called, in whatever language the account happens to use.
//
// The harness matched English strings -- 'Call', 'Answer', 'Hang up' -- and
// the app does not render in English for everybody. It renders in the user's
// own language, and the two fixture accounts are language learners, so one of
// them drives a Hindi UI. The scenarios then failed with "the call controls
// never appeared" while the screenshot showed the call controls, plainly, in
// Hindi. A whole afternoon of the failure looking like a product bug.
//
// The fix is not to force the accounts into English. It is to stop assuming
// the product speaks English at all: every label is resolved to the set of
// strings the app could actually render for it, read from the app's OWN
// translation files, and a match against any one of them is a match.
//
// This also removes a quieter hazard. A hardcoded English string in here goes
// stale the moment somebody edits the arb, and it goes stale SILENTLY -- the
// control is simply never found again. Reading the same file the app reads
// means the harness cannot drift away from the product.

const fs = require('fs');
const path = require('path');

/// Where the app keeps its strings. Resolved from this file, so a checkout
/// anywhere works and a worktree does not need configuring.
const L10N_DIR = path.resolve(__dirname, '..', '..', 'lib', 'l10n');

let cache = null;

/// Every arb, parsed once.
///
/// Roughly a hundred and twenty files, read on the first lookup and kept. A
/// scenario asks for a handful of labels dozens of times over a run, and
/// re-reading the set per question turned a cheap question into a slow one.
function allArbs() {
  if (cache) return cache;
  cache = [];
  let names;
  try {
    names = fs.readdirSync(L10N_DIR).filter((f) => /^intl_.*\.arb$/.test(f));
  } catch (e) {
    throw new Error(
      `Cannot read the app's translations at ${L10N_DIR}: ${e.message}. ` +
        `The harness resolves every UI label from them.`,
    );
  }
  for (const name of names) {
    try {
      cache.push(JSON.parse(fs.readFileSync(path.join(L10N_DIR, name), 'utf8')));
    } catch {
      // A single unparseable translation must not take the harness down: the
      // other hundred still answer the question, and English is among them.
    }
  }
  if (!cache.length) {
    throw new Error(`No readable translations found in ${L10N_DIR}`);
  }
  return cache;
}

/// Every rendering of one l10n key, across every language, deduplicated.
///
/// Throws on a key no translation defines. That is nearly always a typo or a
/// key that has been renamed in the app, and it is worth failing loudly at the
/// first lookup rather than searching the screen for a string that cannot be
/// there and reporting the control as missing.
function labelsFor(key) {
  let defined = false;
  const out = new Set();
  for (const arb of allArbs()) {
    const v = arb[key];
    if (typeof v !== 'string' || !v.length) continue;
    defined = true;

    // Placeholders are not ours to fill, so a string carrying one is matched
    // on its longest LITERAL RUN -- the longest stretch the app draws
    // verbatim, whatever it interpolates around it.
    //
    // The obvious rule, "take the prefix before the first {", is wrong in the
    // way that matters: "{name} did not say anything" begins WITH the
    // placeholder, so its prefix is the empty string, every candidate is
    // dropped, and the caller is handed an empty set. A check written against
    // an empty set cannot fail. That is exactly what happened to the
    // "nobody who spoke is reported as silent" assertion -- it read as
    // coverage for a whole afternoon and could never once have caught
    // anything.
    const literal = v
      .split(/\{[^}]*\}/)
      .map((part) => part.trim())
      .sort((a, b) => b.length - a.length)[0];
    if (literal && literal.length >= 3) out.add(literal);
  }

  if (!defined) {
    throw new Error(
      `No translation defines "${key}". The app has probably renamed it; ` +
        `check lib/l10n/intl_en.arb.`,
    );
  }
  // Defined everywhere and still nothing to match on: every rendering is
  // placeholders and punctuation. Silently returning [] would hand back a
  // question that always answers "no", so say so instead.
  if (!out.size) {
    throw new Error(
      `"${key}" has no literal text to match on in any language -- every ` +
        `rendering is placeholders. It cannot be found on screen by label.`,
    );
  }
  return [...out];
}

/// The labels this harness drives, by the l10n key the app uses for each.
///
/// Named here rather than at each call site so that a key the app renames is
/// one edit, and so that reading this file tells you every string the harness
/// depends on.
const KEYS = {
  call: 'startCall',
  videoCall: 'startVideoCall',
  answer: 'callAnswer',
  decline: 'callDecline',
  hangup: 'callHangUp',
  mute: 'callMute',
  ret: 'callReturn',
  busy: 'callFailedBusy',
  recordingNotice: 'callRecordingNotice',
  transcriptLink: 'callTranscriptOpen',
  // The composer. Present ONLY inside an open chat, which is what makes it a
  // sound confirmation that navigation landed. The call buttons are not: they
  // also render on the home map, so confirming on them let `openRoom` and
  // `ensureRoom` both report success while the app sat on the map, and the
  // transcript-card check then looked for a card that was never on screen.
  composer: 'writeAMessage',
};

const memo = {};

/// Every string that could be the named control, in any language.
function candidates(name) {
  if (!(name in KEYS)) {
    throw new Error(
      `Unknown control "${name}". Known: ${Object.keys(KEYS).join(', ')}`,
    );
  }
  if (!memo[name]) memo[name] = labelsFor(KEYS[name]);
  return memo[name];
}

/// Every RAW rendering of a key, placeholders intact.
///
/// `labelsFor` returns the literal runs, which is what you match a control by.
/// This returns the templates themselves, which is what you use when you know
/// what goes IN the placeholder: substituting the value the app would draw
/// gives the exact string on screen, and an exact string needs no window
/// around it to decide who it is about.
function templatesFor(key) {
  const out = new Set();
  for (const arb of allArbs()) {
    const v = arb[key];
    if (typeof v === 'string' && v.length) out.add(v);
  }
  if (!out.size) throw new Error(`No translation defines "${key}".`);
  return [...out];
}

module.exports = { candidates, labelsFor, templatesFor, KEYS, L10N_DIR };
