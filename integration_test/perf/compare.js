// Compares two sets of performance-benchmark result files from the same
// device and account (testing.instructions.md § Performance benchmark).
//
//   node integration_test/perf/compare.js --base <files...> --new <files...>
//
// Each run is reduced to one value per metric: the median of its passes,
// leaving out the first, which carries one-time costs (image decode, first
// layout). The baseline's noise band is the gap between its highest and lowest
// run, with a floor of 5% of the baseline so a perfectly steady metric cannot
// flag a one-frame wobble. A metric counts as changed when the new runs'
// median moves more than twice that band. A band from a handful of runs
// understates the real spread: identical code measured against itself moved up
// to 1.3 times its band, while a 3 ms-per-row slowdown moved over 3 times.
// Interleave the two builds' runs (A, B, A, B...) so drift over the session
// lands on both, and use at least three runs of each.

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
if (!baseFiles.length || !newFiles.length) {
  console.error('Usage: compare.js --base <result files...> --new <result files...>');
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

const load = (files) => {
  const runs = files.map((f) => JSON.parse(fs.readFileSync(f, 'utf8')));
  const keys = new Set(runs.map((r) => `${r.scenario} / ${r.platform} / ${r.refreshRate} Hz`));
  return { runs, keys };
};
const base = load(baseFiles);
const next = load(newFiles);
const all = new Set([...base.keys, ...next.keys]);
if (all.size !== 1) {
  console.error(`Results are not comparable: ${[...all].join(' vs ')}`);
  process.exit(2);
}
console.log(`${[...all][0]}: ${base.runs.length} baseline run(s) vs ${next.runs.length} new run(s), first pass of each left out`);

const round = (v) => Math.round(v * 10) / 10;
const median = (values) => {
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
};
const runValues = (set, pick) => set.runs.map((r) => median(r.passes.slice(1).map(pick)));
if (base.runs.length < 3) console.warn('Fewer than three baseline runs: the noise band is not trustworthy.');
let changed = 0;
const rows = Object.entries(METRICS).map(([name, pick]) => {
  const b = runValues(base, pick);
  const n = runValues(next, pick);
  const band = Math.max(Math.max(...b) - Math.min(...b), 0.05 * Math.abs(median(b)));
  const delta = median(n) - median(b);
  const verdict = Math.abs(delta) <= 2 * band ? 'no change' : delta > 0 ? 'WORSE' : 'better';
  if (verdict !== 'no change') changed++;
  return {
    metric: name,
    baseline: round(median(b)),
    'flag above': `±${round(2 * band)}`,
    new: round(median(n)),
    change: `${delta >= 0 ? '+' : ''}${round(delta)}`,
    verdict,
  };
});
console.table(rows);
process.exit(changed ? 1 : 0);
