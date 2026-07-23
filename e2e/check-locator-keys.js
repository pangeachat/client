#!/usr/bin/env node
/**
 * Fail when an e2e spec targets an l10n key the app no longer renders.
 *
 * Specs address widgets by their accessible name, which they read out of
 * lib/l10n/intl_en.arb. Nothing ties that key back to a widget: delete or rename
 * the widget and the key survives, still resolving to a real English string. The
 * spec keeps compiling and the locator simply never matches — so the test rots
 * silently and only surfaces weeks later as a red nightly run against deployed
 * staging, un-attributable to the commit that caused it.
 *
 * Four specs had rotted this way before this check existed (yourPublicKey,
 * learningAnalytics, profile, home). This makes that failure land on the PR that
 * removes the widget, which is the only place it is cheap to fix.
 *
 * Usage: node e2e/check-locator-keys.js
 */
const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const SPEC_DIR = path.join(__dirname, "scripts");
const ARB = path.join(ROOT, "lib/l10n/intl_en.arb");
const ALLOWLIST = path.join(__dirname, "locator-keys-allowlist.json");

/** Strip // line comments and block comments so commented-out widgets don't count as renderers. */
function stripComments(src) {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .split("\n")
    .map((l) => (/^\s*\/\//.test(l) ? "" : l))
    .join("\n");
}

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith(".dart")) out.push(p);
  }
  return out;
}

const arb = JSON.parse(fs.readFileSync(ARB, "utf-8"));
const allow = fs.existsSync(ALLOWLIST)
  ? JSON.parse(fs.readFileSync(ALLOWLIST, "utf-8"))
  : {};

// Every intl.<key> a spec uses in a locator.
const used = new Map(); // key -> [ "file:line", ... ]
for (const f of fs.readdirSync(SPEC_DIR).filter((f) => f.endsWith(".ts"))) {
  const lines = fs.readFileSync(path.join(SPEC_DIR, f), "utf-8").split("\n");
  lines.forEach((line, i) => {
    if (/^\s*(\/\/|\*)/.test(line)) return; // commented-out spec code
    for (const m of line.matchAll(/\bintl\.([A-Za-z_][A-Za-z0-9_]*)/g)) {
      if (!used.has(m[1])) used.set(m[1], []);
      used.get(m[1]).push(`${f}:${i + 1}`);
    }
  });
}

// Every l10n key the app actually renders, read through an l10n receiver so an
// unrelated `someModel.profile` never counts as a renderer. Whitespace-tolerant
// because dart format wraps `L10n.of(\n  context,\n).key`.
const rendered = new Set();
const dartSrc = walk(path.join(ROOT, "lib"))
  .filter((p) => !p.includes(`${path.sep}l10n${path.sep}`))
  .map((p) => stripComments(fs.readFileSync(p, "utf-8")))
  .join("\n");
for (const m of dartSrc.matchAll(
  /(?:\bl10n|L10n\s*\.\s*of\s*\([\s\S]{0,80}?\))\s*\.\s*([A-Za-z_][A-Za-z0-9_]*)/g,
)) {
  rendered.add(m[1]);
}

const dead = [];
for (const [key, sites] of used) {
  if (rendered.has(key) || key in allow) continue;
  dead.push({ key, sites, english: arb[key], inArb: key in arb });
}

if (dead.length === 0) {
  console.log(`OK — all ${used.size} locator keys are rendered by live Dart.`);
  process.exit(0);
}

console.error(`\n${dead.length} e2e locator key(s) reference UI the app no longer renders:\n`);
for (const d of dead) {
  console.error(`  intl.${d.key}  ${d.inArb ? `= ${JSON.stringify(d.english)}` : "(NOT IN ARB)"}`);
  console.error(`      used at: ${d.sites.join(", ")}`);
  console.error(
    `      no non-commented lib/ code renders it — the locator can never match.\n`,
  );
}
console.error(
  "Fix the spec to target a control that exists, or delete the assertion.\n" +
    `If the key really is rendered through indirection this check cannot see, add it to\n` +
    `e2e/locator-keys-allowlist.json with a reason.\n`,
);
process.exit(1);
