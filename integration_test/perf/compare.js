// Compares two versions' performance-benchmark result files from the same
// device and account (testing.instructions.md § Performance benchmark).
//
//   node integration_test/perf/compare.js --base <files...> --new <files...>
//
// Run the two versions alternately (A, B, A, B...) and list each side's files
// in run order, so the Nth baseline file and the Nth new file come from the
// same round. Each run is reduced to one value per metric: the median of its
// passes, leaving out the first, which carries one-time costs (image decode,
// first layout). Each round then gives one difference per metric, and a metric
// counts as changed when it moved the same way in every round by more than 5%
// of the baseline. A slowdown that hits the whole device for a while lands on
// both runs of its round and cancels out.

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
};

const load = (files) => files.map((f) => JSON.parse(fs.readFileSync(f, 'utf8')));
const base = load(baseFiles);
const next = load(newFiles);
const keys = new Set([...base, ...next].map((r) => `${r.scenario} / ${r.platform} / ${r.refreshRate} Hz`));
if (keys.size !== 1) {
  console.error(`Results are not comparable: ${[...keys].join(' vs ')}`);
  process.exit(2);
}
console.log(`${[...keys][0]}: ${base.length} rounds, first pass of each run left out`);

const round = (v) => Math.round(v * 10) / 10;
const median = (values) => {
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
};
const runValues = (runs, pick) => runs.map((r) => median(r.passes.slice(1).map(pick)));

let changed = 0;
const rows = Object.entries(METRICS).map(([name, pick]) => {
  const b = runValues(base, pick);
  const deltas = runValues(next, pick).map((v, i) => v - b[i]);
  const floor = 0.05 * Math.abs(median(b));
  const verdict = deltas.every((d) => d > floor) ? 'WORSE' : deltas.every((d) => d < -floor) ? 'better' : 'no change';
  if (verdict !== 'no change') changed++;
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
