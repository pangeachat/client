// Route 11 (pangeachat/2-step-choreographer#3350). Voice, neither subscribed: no transcript, the lock, the audio still saved (#8792).
const R = require('./lib');
const { runStandardCall } = require('./standard');

runStandardCall({
  id: 'r11_voice_neither',
  title: 'Voice, neither subscribed: no transcript, the lock, the audio still saved (#8792).',
  sub: { A: false, B: false },
  wavA: R.fixture('learner'), wavB: R.fixture('peer'),
  talkS: 35,
});
