// Route 5 (pangeachat/2-step-choreographer#3350): voice, both subscribed, the
// learner switches device at ~150s ("Use this device"). client#9173,
// client#8878, choreo#3354.
const { runSwitch } = require('./switch');

runSwitch({ id: 'r05b_voice_both_switch150', moveAtS: 150, talkAfterS: 40 });
