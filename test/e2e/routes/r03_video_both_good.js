// Route 3 (pangeachat/2-step-choreographer#3350). Video, both subscribed, good network.
const R = require('./lib');
const { runStandardCall } = require('./standard');

runStandardCall({
  id: 'r03_video_both_good',
  title: 'Video, both subscribed, good network.',
  video: true,
  sub: { A: true, B: true },
  wavA: R.fixture('learner'), wavB: R.fixture('peer'),
  talkS: 50,
});
