// Route 5 (pangeachat/2-step-choreographer#3350): voice, both subscribed, the
// learner switches device at ~75s ("Use this device"). client#9173,
// client#8878, choreo#3354.
const { runSwitch } = require('./switch');

runSwitch({ id: 'r05a_voice_both_switch75', moveAtS: 75, talkAfterS: 40 });
