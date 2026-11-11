// Route 2 (pangeachat/2-step-choreographer#3350). Voice, one subscribed, both browsers throttled (DevTools: 400ms, 50/25 KB/s) through the call AND the upload (#3379).
const R = require('./lib');
const { runStandardCall } = require('./standard');

runStandardCall({
  id: 'r02_voice_one_throttled',
  title: 'Voice, one subscribed, both browsers throttled (DevTools: 400ms, 50/25 KB/s) through the call AND the upload (#3379).',
  sub: { A: true, B: false },
  network: { mode: 'throttled' },
  wavA: R.fixture('learner'), wavB: R.fixture('peer'),
  // At 50/25 KB/s the throttled half's upload and the merge it gates land
  // 500-610 s after hang-up (measured); 900 s leaves margin. Owner-approved.
  talkS: 50, settleS: 900,
});
