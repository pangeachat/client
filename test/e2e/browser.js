// The browser a participant is. One real Chrome, with a fake microphone
// playing a real wav file.
//
// Real Chrome rather than headless anything, because the thing under test is
// WebRTC: a call needs a media stack, an autoplay policy, and a device
// enumeration that behave the way a learner's browser behaves. The fake
// devices are the only pretence -- and they are fed a file, not a tone, so a
// recording made during a scenario has something in it worth transcribing.
const fs = require('fs');
const puppeteer = require('puppeteer-core');
const cfg = require('./config');

/// Fails NOW, with the setting to change, rather than at the first click.
///
/// puppeteer-core ships no browser of its own. Without this the run dies
/// inside puppeteer with a spawn ENOENT naming a path nobody set, which reads
/// like a broken harness rather than a missing install.
function chromePath() {
  if (!fs.existsSync(cfg.chrome)) {
    throw new Error(
      `no Chrome at ${cfg.chrome}. Set CHROME to the executable inside your `
      + 'install (on macOS: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", '
      + 'on Linux typically /usr/bin/google-chrome or /usr/bin/chromium).');
  }
  return cfg.chrome;
}

/// The fake microphone has to be fed real speech, or the run is a lie where
/// it matters most.
///
/// Chrome falls back to a generated tone when the file is missing, and a tone
/// transcribes to nothing -- so every recording and analytics assertion still
/// "passes" while proving the opposite of what it says. A missing file is
/// therefore a refusal, naming the setting to change. Somebody who genuinely
/// only wants the signalling scenarios says so out loud with
/// CALL_ALLOW_SILENT=1 and gives up those checks knowingly.
function fakeAudio(wav) {
  if (fs.existsSync(wav)) return wav;
  if (process.env.CALL_ALLOW_SILENT === '1') {
    console.log(`   (no audio at ${wav}; running silent by CALL_ALLOW_SILENT. `
      + 'Anything about recording or transcripts proves nothing this run.)');
    return wav;
  }
  throw new Error(
    `no fake-microphone audio at ${wav}. Point CALL_CALLER_WAV / `
    + 'CALL_CALLEE_WAV at two wav files of real speech (16-bit PCM), or set '
    + 'CALL_ALLOW_SILENT=1 to run without the recording checks meaning '
    + 'anything.');
}

async function launch({ userDataDir, wav, port }) {
  const browser = await puppeteer.launch({
    executablePath: chromePath(),
    headless: false,
    userDataDir,
    args: [
      // Grant the microphone without a prompt, and make it a file rather than
      // a real device: a scenario cannot answer a permission dialog, and a
      // laptop's real microphone would put the room's own audio back into it.
      '--use-fake-ui-for-media-stream',
      '--use-fake-device-for-media-stream',
      `--use-file-for-fake-audio-capture=${fakeAudio(wav)}%noloop`,
      // And let the audio service actually READ that file.
      //
      // The fake microphone is fed by the audio service, which runs in its own
      // sandboxed process, and on macOS that sandbox denies it the fixture.
      // Chrome does not fail the capture over it: `media/audio/simple_sources.cc`
      // logs "Failed to read <path> as input to the fake device. Try disabling
      // the sandbox with --no-sandbox." once per capture, and then hands out
      // DIGITAL SILENCE -- exact zeroes -- for the rest of the call.
      //
      // Which is the worst shape this could take. Everything that is about the
      // CALL still passes: it rings, it is answered, both halves are written,
      // each under its own sender, with turn positions. Only the words are
      // gone, replaced by whatever a provider says about twenty seconds of
      // nothing -- Whisper answers "you". That reads exactly like a broken
      // transcript pipeline in the app, and three theories about the app's
      // capture path were chased before Chrome's own log line was read.
      //
      // This IS a reduction in Chrome's sandboxing, and it belongs to the
      // harness alone: these browsers are launched by this file, run against a
      // laptop's local stack, and are thrown away at the end of a scenario.
      // Nothing ships it. It also disables the audio service's sandbox
      // ENTIRELY, and only that one: narrower than the `--no-sandbox` the log
      // line suggests, which lifts the RENDERER sandbox too, and the renderer
      // is the process running the app under test.
      '--disable-features=AudioServiceSandbox',
      // Ringtones and remote audio start without a click, which no scenario
      // can supply.
      '--autoplay-policy=no-user-gesture-required',
      '--no-first-run', '--no-default-browser-check',
      // The port is how a probe attaches to a running participant.
      `--remote-debugging-port=${port}`,
      '--window-size=1000,720',
    ],
    // Fixed, because the call panel and the ring banner are partly driven by
    // position: a viewport that moved would move them.
    defaultViewport: { width: 1000, height: 700 },
  });
  return browser;
}

module.exports = { launch, chromePath };
