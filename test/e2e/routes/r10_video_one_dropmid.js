// Route 10 (pangeachat/2-step-choreographer#3350). Video, one subscribed; the callee goes offline (DevTools) for 10s mid-call (inside the 20s peer grace), then back.
const R = require('./lib');
const { runStandardCall } = require('./standard');

runStandardCall({
  id: 'r10_video_one_dropmid',
  title: 'Video, one subscribed; the callee goes offline (DevTools) for 10s mid-call (inside the 20s peer grace), then back.',
  video: true,
  sub: { A: true, B: false },
  network: { mode: 'dropMid', who: 'B' }, dropAtS: 20, dropForS: 10,
  wavA: R.fixture('learner'), wavB: R.fixture('peer'),
  talkS: 70,
});
