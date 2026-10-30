// Route 13 (acoustic) (pangeachat/2-step-choreographer#3350). Voice, both subscribed, background noise + music mixed under both voices (#3356).
const R = require('./lib');
const { runStandardCall } = require('./standard');

runStandardCall({
  id: 'r13_voice_both_noisy',
  title: 'Voice, both subscribed, background noise + music mixed under both voices (#3356).',
  sub: { A: true, B: true },
  wavA: R.fixture('learner_noisy'), wavB: R.fixture('peer_noisy'),
  checkRepetition: true,
  talkS: 50,
});
