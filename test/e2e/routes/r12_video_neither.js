// Route 12 (pangeachat/2-step-choreographer#3350). Video, neither subscribed: the locked transcript, with no per-half note behind it (#8791).
const R = require('./lib');
const { runStandardCall } = require('./standard');

runStandardCall({
  id: 'r12_video_neither',
  title: 'Video, neither subscribed: the locked transcript, with no per-half note behind it (#8791).',
  video: true,
  sub: { A: false, B: false },
  wavA: R.fixture('learner'), wavB: R.fixture('peer'),
  talkS: 35,
});
