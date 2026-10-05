// Compares two versions' performance-benchmark result files from the same
// device and account (testing.instructions.md § Performance benchmark).
//
//   node integration_test/perf/compare.js --base <files...> --new <files...>
//
// Run the two versions alternately (A, B, A, B...) and list each side's files
// in run order, so the Nth baseline file and the Nth new file come from the
// same round. Each run is reduced to one value per metric: the median of its
// passes, leaving out its warm-up passes (a scroll run's first pass carries
// one-time costs such as image decode; a launch run has no warm-up, since its
// one pass is the launch). Each round then gives one difference per metric,
// and a metric counts as changed when it moved the same way in every round:
// by more than 5% of the baseline and at least 0.1 ms for a time, and by more
// than a quarter of the baseline and at least 3 frames for a count of frames
// over budget. A time whose change in every round is under 0.5 ms needs at
// least five rounds. Counts swing much more than times between identical
// runs. A slowdown that hits the whole device for a while lands on both runs
// of its round and cancels out.

const fs = require('fs');

const args = process.argv.slice(2);
const group = (flag) => {
  const start = args.indexOf(flag);
  if (start === -1) return [];
  const rest = args.slice(start + 1);
  const end = rest.findIndex((a) => a.startsWith('--'));
  return end === -1 ? rest : rest.slice(0, end);
};
const baseFiles = group('--base');
const newFiles = group('--new');
if (baseFiles.length < 3 || baseFiles.length !== newFiles.length) {
  console.error('Usage: compare.js --base <files...> --new <files...>, the same number of each, at least three, in run order.');
  process.exit(2);
}

const METRICS = {
  'build p50 (ms)': (p) => p.buildMs.p50,
  'build p90 (ms)': (p) => p.buildMs.p90,
  'raster p50 (ms)': (p) => p.rasterMs.p50,
  'raster p90 (ms)': (p) => p.rasterMs.p90,
  'missed build budget': (p) => p.missedBuildBudget,
  'missed raster budget': (p) => p.missedRasterBudget,
  'first frame build (ms)': (p) => p.firstFrameBuildMs,
  'first frame raster (ms)': (p) => p.firstFrameRasterMs,
  'total build (ms)': (p) => p.totalBuildMs,
};

const load = (files) => files.map((f) => JSON.parse(fs.readFileSync(f, 'utf8')));
const base = load(baseFiles);
const next = load(newFiles);
const keys = new Set([...base, ...next].map((r) => `${r.scenario}${r.target ? ` (${r.target})` : ''} / ${r.platform} / ${r.refreshRate} Hz`));
if (keys.size !== 1) {
  console.error(`Results are not comparable: ${[...keys].join(' vs ')}`);
  process.exit(2);
}
console.log(`${[...keys][0]}: ${base.length} rounds`);

const round = (v) => Math.round(v * 10) / 10;
const median = (values) => {
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
};
const runValues = (runs, pick) => runs.map((r) => median(r.passes.slice(r.warmupPasses ?? 1).map(pick)));
// Scenario-specific metrics (the launch ones) appear only where every run has them.
const present = (pick) => [...base, ...next].every((r) => r.passes.slice(r.warmupPasses ?? 1).every((p) => typeof pick(p) === 'number'));

let changed = 0;
// An interaction scenario's actions: each kind's total build and raster time
// per action (testing.instructions.md § Performance benchmark).
const actionKinds = new Set([...base, ...next].flatMap((r) => r.passes.flatMap((p) => Object.keys(p.actions ?? {}))));
for (const kind of actionKinds) {
  METRICS[`${kind}: build (ms)`] = (p) => p.actions?.[kind]?.buildMs;
  METRICS[`${kind}: raster (ms)`] = (p) => p.actions?.[kind]?.rasterMs;
}

const rows = Object.entries(METRICS).filter(([, pick]) => present(pick)).map(([name, pick]) => {
  const b = runValues(base, pick);
  const deltas = runValues(next, pick).map((v, i) => v - b[i]);
  const baseline = Math.abs(median(b));
  const isCount = name.startsWith('missed');
  const floor = isCount ? Math.max(0.25 * baseline, 3) : Math.max(0.05 * baseline, 0.1);
  // Rounded to hundredths, so a printed +0.1 means the same to the rule.
  const r2 = (d) => Math.round(d * 100) / 100;
  const beyond = (d) => (isCount ? d > 0.25 * baseline && d >= 3 : d > 0.05 * baseline && r2(d) >= 0.1);
  const moved = deltas.every(beyond) ? 'WORSE' : deltas.every((d) => beyond(-d)) ? 'better' : 'no change';
  // A small time change needs more rounds before a streak can't be chance.
  const small = !isCount && deltas.every((d) => Math.abs(d) < 0.5);
  const verdict = moved !== 'no change' && small && deltas.length < 5 ? 'needs 5 rounds' : moved;
  if (verdict === 'WORSE' || verdict === 'better') changed++;
  return {
    metric: name,
    baseline: round(median(b)),
    'change per round': deltas.map((d) => `${d >= 0 ? '+' : ''}${round(d)}`).join(', '),
    'needs beyond': `±${round(floor)}`,
    verdict,
  };
});
console.table(rows);
process.exit(changed ? 1 : 0);
