// Route 4 (pangeachat/2-step-choreographer#3350). Voice, both subscribed; the callee network drops at call end, the callee app is SIGKILLed during upload and reopened (#9302, #3351 context).
const R = require('./lib');
const { runStandardCall } = require('./standard');

runStandardCall({
  id: 'r04_voice_both_dropend_kill',
  title: 'Voice, both subscribed; the callee network drops at call end, the callee app is SIGKILLed during upload and reopened (#9302, #3351 context).',
  sub: { A: true, B: true },
  network: { mode: 'dropEnd', who: 'B' },
  killDuringUpload: true, killForS: 15,
  wavA: R.fixture('learner'), wavB: R.fixture('peer'),
  talkS: 50, settleS: 360,
});
