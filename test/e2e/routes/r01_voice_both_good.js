// Route 1 (pangeachat/2-step-choreographer#3350). Voice, both subscribed, good network, quiet fixtures (web stands in for iOS<->iPad).
const R = require('./lib');
const { runStandardCall } = require('./standard');

runStandardCall({
  id: 'r01_voice_both_good',
  title: 'Voice, both subscribed, good network, quiet fixtures (web stands in for iOS<->iPad).',
  sub: { A: true, B: true },
  wavA: R.fixture('learner'), wavB: R.fixture('peer'),
  talkS: 50,
});
