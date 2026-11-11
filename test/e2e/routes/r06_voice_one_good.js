// Route 6 (pangeachat/2-step-choreographer#3350). Voice, one subscribed, good network: the subscriber reads both sides (#8792).
const R = require('./lib');
const { runStandardCall } = require('./standard');

runStandardCall({
  id: 'r06_voice_one_good',
  title: 'Voice, one subscribed, good network: the subscriber reads both sides (#8792).',
  sub: { A: true, B: false },
  wavA: R.fixture('learner'), wavB: R.fixture('peer'),
  talkS: 50,
});
