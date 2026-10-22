// Route 15 (language) (pangeachat/2-step-choreographer#3350). Voice, both subscribed, an en->fr learner speaking French (L2) and English (L1) (#3382, #3351).
const R = require('./lib');
const { runStandardCall } = require('./standard');

runStandardCall({
  id: 'r15_voice_fr_l1l2',
  title: 'Voice, both subscribed, an en->fr learner speaking French (L2) and English (L1) (#3382, #3351).',
  A: 'routes_fr', room: 'fr_calltester', langA: 'fr',
  sub: { A: true, B: true },
  wavA: R.fixture('fr_mix'), wavB: R.fixture('peer'),
  wordsA: R.WORDS.frL2, l1Words: R.WORDS.frL1,
  talkS: 50,
});
