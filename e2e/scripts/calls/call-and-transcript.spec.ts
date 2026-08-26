import fs from "fs";
import path from "path";
import { expect, test, type BrowserContext, type Page } from "@playwright/test";

/**
 * A real 1:1 call, end to end, with two distinct voices.
 *
 * Why this exists rather than a checklist item somebody works through by hand:
 * a call needs two parties, and this machine has one microphone. Driving it by
 * hand means both sides capture the same room, so per-speaker attribution --
 * the thing the transcript is FOR -- is the one property that cannot be
 * checked. Chromium's fake capture gives each context its own WAV, so the two
 * halves carry provably different speech and the assertion is real.
 *
 * Requires the local stack (Synapse, choreo, LiveKit, lk-jwt) and the app
 * served at BASE_URL. See docs/handoff/2026-08-25-calls-e2e-plan.md.
 *
 * Triggers:
 * - lib/routes/chat/calls/**
 * - lib/utils/client_manager.dart
 */

/**
 * The strings of the app UNDER TEST, which is not always this checkout.
 *
 * The calls work lives in a worktree, so its l10n keys exist there and not
 * here. Reading this checkout's arb resolved every call locator to undefined,
 * which Playwright widened to "every button on the page" -- a failure that
 * looks like a broken app and is really a spec pointed at the wrong strings.
 */
const intl = JSON.parse(
  fs.readFileSync(
    process.env.ARB_PATH ||
      path.resolve(__dirname, "../../../lib/l10n/intl_en.arb"),
    "utf-8",
  ),
);

/** Fails loudly rather than letting an absent key widen a locator. */
function str(key: string): string {
  const v = intl[key];
  if (typeof v !== "string") {
    throw new Error(
      `l10n key "${key}" is missing from the arb under test. ` +
        `Set ARB_PATH to the checkout whose app is being served.`,
    );
  }
  return v;
}

/** Two accounts the local stack is seeded with. */
const CALLER = { user: "learner", pass: "learnerpass" };
const CALLEE = { user: "calltester", pass: "calltesterpass" };

/**
 * A context whose microphone is a file, so this side has its own voice.
 *
 * The file is passed per-context rather than per-project because the whole
 * point is that the two sides differ; a project-level flag would give both
 * halves identical audio and the attribution assertion would pass while
 * proving nothing.
 */
async function contextSpeaking(
  browser: import("@playwright/test").Browser,
  wav: string,
): Promise<BrowserContext> {
  return browser.newContext({
    permissions: ["microphone"],
    // Chromium reads the file as raw capture. Absent, the fake device emits a
    // tone, which transcribes to nothing and would make an empty transcript
    // look like a passing test.
    launchOptions: {
      args: [`--use-file-for-fake-audio-capture=${wav}`],
    },
  } as Parameters<typeof browser.newContext>[0]);
}

/** Flutter draws to canvas; the semantics tree is the only thing to drive. */
async function openApp(page: Page): Promise<void> {
  await page.goto("/");

  // Flutter boots, THEN paints, THEN exposes the semantics placeholder.
  // Clicking before that leaves the tree empty and every later locator fails
  // with "element not found", which reads like a broken app rather than a
  // test that went too early.
  const enable = page.getByRole("button", { name: "Enable accessibility" });
  await enable.waitFor({ state: "attached", timeout: 90000 });
  await enable.dispatchEvent("click", { timeout: 15000 });

  // The placeholder disappearing is the signal that semantics are live --
  // a fixed sleep either wastes time or races the slower machine.
  await enable.waitFor({ state: "detached", timeout: 60000 });
}

async function signIn(page: Page, who: { user: string; pass: string }) {
  await openApp(page);
  await page.getByRole("button", { name: str("loginToAccount") }).click();
  await page.getByRole("button", { name: str("email") }).click();

  const username = page.getByRole("textbox", { name: str("usernameOrEmail") });
  await username.click();
  await username.fill(who.user);

  const password = page.getByRole("textbox", { name: str("password") });
  await password.click();
  // Flutter needs a beat between focus and input, or the field takes the
  // click and drops the text. The login-logout spec learned this already.
  await page.waitForTimeout(500);
  await password.fill(who.pass);

  // Waiting for ENABLED rather than clicking blind: the button only enables
  // once both fields registered, so this is what distinguishes "the app
  // rejected the credentials" from "the text never arrived".
  const login = page.getByRole("button", { name: str("login") });
  await expect(login).toBeEnabled({ timeout: 15000 });
  await login.click();

  // Leaving the login flow is the signal a session exists.
  await expect(page).not.toHaveURL(/\/login/, { timeout: 120000 });
  await page.waitForTimeout(3000);
}

test.describe("a 1:1 call, from ring to transcript", () => {
  // Two Flutter apps boot, sign in, hold a real call, and wait for a real
  // speech provider. The default budget is for a page interaction, not for
  // this, and a timeout here reads as a product failure when it is only the
  // clock.
  test.setTimeout(360000);

  test("both speakers' words survive the call and are attributed", async ({
    browser,
  }) => {
    const speech = path.resolve(__dirname, "fixtures");
    const callerCtx = await contextSpeaking(
      browser,
      path.join(speech, "caller.wav"),
    );
    const calleeCtx = await contextSpeaking(
      browser,
      path.join(speech, "callee.wav"),
    );

    try {
      const caller = await callerCtx.newPage();
      const callee = await calleeCtx.newPage();

      await Promise.all([signIn(caller, CALLER), signIn(callee, CALLEE)]);

      // The ring must reach the other side. Asserted before answering,
      // because a banner that never appears and a call that never connects
      // fail at the same later step otherwise, and they are different bugs.
      // Into the conversation first. Login lands on the world map, and the
      // call buttons live in the chat header -- clicking for them from the map
      // is how a spec ends up matching every button on the page.
      await caller.getByRole("button", { name: str("allChats") }).click();
      await caller.getByRole("button", { name: CALLEE.user }).first().click();

      await callee.getByRole("button", { name: str("allChats") }).click();

      await caller.getByRole("button", { name: str("startCall") }).click();
      await expect(
        callee.getByRole("button", { name: str("callAnswer") }),
      ).toBeVisible({ timeout: 30000 });

      await callee.getByRole("button", { name: str("callAnswer") }).click();

      // Consent is part of the product promise, not decoration.
      await expect(
        caller.getByText(str("callRecordingNotice"), { exact: false }),
      ).toBeVisible({ timeout: 30000 });

      // Long enough for the chunker to cut and ship several chunks. Shorter
      // and an empty transcript would mean "we did not wait", not "it broke".
      await caller.waitForTimeout(20000);

      await caller.getByRole("button", { name: str("callHangUp") }).click();

      // The card is written at hangup and must not wait for transcription.
      const card = caller.getByText(str("callHistoryVoiceCall"), {
        exact: false,
      });
      await expect(card).toBeVisible({ timeout: 20000 });

      await card.click();
      await expect(
        caller.getByText(str("callTranscriptTitle"), { exact: false }),
      ).toBeVisible({ timeout: 30000 });

      // The assertions this whole file exists for.
      //
      // First, honesty: neither speaker is reported as absent or as having
      // said nothing. The l10n strings interpolate a name, so the placeholder
      // is stripped and the remainder used as a substring -- matching on the
      // fixed part is what makes this independent of who the accounts are.
      await expect(
        caller.getByText(str("callTranscriptSaidNothing").replace("{name}", "")),
      ).toHaveCount(0);
      await expect(
        caller.getByText(str("callTranscriptNone").replace("{name}", "")),
      ).toHaveCount(0);

      // Then attribution, which is the property a hand-driven test on one
      // microphone can never check. The two contexts were handed DIFFERENT
      // WAVs, so if only one speaker's words come back, the pipeline has
      // crossed the halves or is transcribing one source twice -- and every
      // check above still passes.
      //
      // What the fixtures say, recorded here because it is the expectation:
      //   caller.wav (Paulina): "Hola, buenas tardes. Me llamo Ana y hoy
      //     quiero hablar contigo sobre mi viaje a Sevilla."
      //   callee.wav (Jorge):   "Claro que si. Cuentame todo sobre Sevilla,
      //     por favor. Yo estuve alli el ano pasado."
      //
      // Flutter paints to canvas, so the words are not DOM text: they reach
      // the page as aria-labels on the semantics nodes. Reading those is the
      // only way to see what was rendered.
      const rendered = (
        await caller.locator("flt-semantics[aria-label]").allTextContents()
      ).join(" ");
      const labels = await caller
        .locator("flt-semantics[aria-label]")
        .evaluateAll((nodes) =>
          nodes.map((n) => n.getAttribute("aria-label") || "").join(" "),
        );
      const said = new Set(
        `${rendered} ${labels}`
          .toLowerCase()
          .split(/[^\p{L}\p{N}]+/u)
          .filter(Boolean),
      );

      // One distinctive word from EACH fixture, so neither side can be
      // satisfied by the other's audio. Chosen without diacritics: the
      // provider decides its own accents and casing, and a test that turns on
      // those fails for a reason that is not a bug.
      for (const [word, whose] of [
        ["tardes", "the caller"],
        ["viaje", "the caller"],
        ["favor", "the callee"],
        ["pasado", "the callee"],
      ] as const) {
        expect(
          said.has(word),
          `"${word}" is spoken by ${whose} and did not reach the transcript`,
        ).toBe(true);
      }
    } finally {
      await callerCtx.close();
      await calleeCtx.close();
    }
  });
});
