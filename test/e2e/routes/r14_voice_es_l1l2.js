// Route 14 (language) (pangeachat/2-step-choreographer#3350). Voice, both subscribed, an en->es learner speaking Spanish (L2) and English (L1) (#3351).
const R = require('./lib');
const { runStandardCall } = require('./standard');

runStandardCall({
  id: 'r14_voice_es_l1l2',
  title: 'Voice, both subscribed, an en->es learner speaking Spanish (L2) and English (L1) (#3351).',
  A: 'routes_es', room: 'es_calltester', langA: 'es',
  sub: { A: true, B: true },
  wavA: R.fixture('es_mix'), wavB: R.fixture('peer'),
  wordsA: R.WORDS.esL2, l1Words: R.WORDS.esL1,
  talkS: 50,
});
