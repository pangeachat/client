import { defineConfig, devices } from "@playwright/test";
import fs from "fs";
import path from "path";

// Load env vars (no dotenv dependency needed). Specs run against staging, so
// prefer the staging profile: client/.env is a switched copy of an env profile
// (matrix-auth.instructions.md) and may hold the LOCAL stack's credentials,
// which don't exist on staging. Precedence: shell env > .env.staging > .env.
for (const file of [".env.staging", ".env"]) {
  const envPath = path.resolve(__dirname, "..", file);
  if (!fs.existsSync(envPath)) continue;
  for (const line of fs.readFileSync(envPath, "utf-8").split("\n")) {
    const match = line.match(/^\s*([\w]+)\s*=\s*['"]?(.+?)['"]?\s*$/);
    if (match && !process.env[match[1]]) process.env[match[1]] = match[2];
  }
}

/**
 * Playwright config for Pangea Chat E2E tests (web).
 * See https://playwright.dev/docs/test-configuration.
 */
/**
 * Refuses to run anything that places a real CALL against a deployed host.
 *
 * The nightly cron runs `mode=full`, which is the whole of `e2e/scripts/`,
 * against https://app.staging.pangea.chat. A call spec swept up by that would
 * dial a real call every night, unattended, against a shared account, and
 * push both halves of the audio through a BILLED speech-to-text provider.
 *
 * Placement is not a safeguard: "it lives outside e2e/scripts" holds only
 * until somebody moves it back. This is the safeguard, and it fails closed --
 * a call spec anywhere under this config, pointed anywhere but a local stack,
 * stops the run rather than quietly spending money.
 *
 * Calls are tested by the harness in client/test/e2e instead, which drives
 * two real browsers and a real phone against a local stack and never runs in
 * CI.
 */
function refuseRemoteCallSpecs(): void {
  const target = process.env.BASE_URL || "";
  const isLocal =
    target === "" ||
    /^https?:\/\/(localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1\])(:|\/|$)/.test(target);
  if (isLocal) return;

  const dir = path.join(__dirname, "scripts");
  if (!fs.existsSync(dir)) return;

  // Judged on what a spec DOES, not what it is called. An earlier version
  // matched filenames containing "call", which any rename walks straight
  // past -- voice.spec.ts, transcript.spec.ts, rtc.spec.ts. What actually
  // makes a spec unsafe against a deployed host is that it opens a
  // microphone or drives the call controls, and those leave marks in the
  // source that a rename does not remove.
  const MARKS = [
    /permissions\s*:\s*\[[^\]]*microphone/i,
    /use-file-for-fake-audio-capture/i,
    /use-fake-device-for-media-stream/i,
    /getUserMedia/i,
    /\bcallAnswer\b|\bcallHangUp\b|\bstartCall\b|\bstartVideoCall\b/,
  ];

  // Every file a spec could reach, not just the spec.
  //
  // Scanning spec bodies alone is defeated by moving one import out: a spec
  // that calls `placeCall()` from a helper carries none of the marks itself.
  // The whole directory is read instead -- helpers included -- so a call
  // placed at any depth still shows up. Coarse on purpose: a false positive
  // here costs a name in an allowlist, and a false negative costs a real
  // call against a deployed host, every night, on somebody's bill.
  // Every executable file, not just TypeScript: a helper written as .js or
  // .mjs under this tree is imported exactly as easily and was a plain way
  // round an earlier version of this.
  const CODE = /\.(ts|tsx|js|mjs|cjs)$/;

  // Comments stripped before matching. This guard's whole job is to notice
  // code that places a call, and a spec that merely EXPLAINS in prose why it
  // does not touch getUserMedia should not be refused for saying the word.
  const stripComments = (src: string) =>
    src.replace(/\/\*[\s\S]*?\*\//g, " ").replace(/(^|[^:])\/\/[^\n]*/g, "$1 ");

  const marked = fs
    .readdirSync(dir, { recursive: true })
    .map(String)
    .filter((f) => CODE.test(f))
    .filter((f) => {
      const body = stripComments(fs.readFileSync(path.join(dir, f), "utf-8"));
      return MARKS.some((m) => m.test(body));
    });

  const offenders = marked;

  if (offenders.length > 0) {
    throw new Error(
      `Refusing to run against ${target}: ${offenders.join(", ")} opens a ` +
        `microphone or drives the call controls, which against a deployed ` +
        `host places a REAL call and bills a speech-to-text provider. Calls ` +
        `belong to the harness in client/test/e2e, which runs against a ` +
        `local stack only.`,
    );
  }
}

refuseRemoteCallSpecs();

export default defineConfig({
  testDir: "./scripts",

  /* Run tests in files in parallel */
  fullyParallel: true,

  /* Fail the build on CI if you accidentally left test.only in the source code. */
  forbidOnly: !!process.env.CI,

  /* Retry on CI only */
  retries: process.env.CI ? 2 : 0,

  /* Opt out of parallel tests on CI. */
  workers: process.env.CI ? 1 : undefined,

  /* Reporter to use. See https://playwright.dev/docs/test-reporters */
  reporter: "html",

  /* Shared settings for all the projects below. See https://playwright.dev/docs/api/class-testoptions. */
  use: {
    /* Base URL to use in actions like `await page.goto('/')`. */
    baseURL: process.env.BASE_URL || "http://localhost:8080",

    /* Collect trace when retrying the failed test. See https://playwright.dev/docs/trace-viewer */
    trace: "on-first-retry",

    /* Screenshot on failure */
    screenshot: "only-on-failure",
  },

  /* Configure projects for major browsers */
  projects: [
    {
      name: "setup",
      testMatch: /.*\.setup\.ts/,
      testDir: "./",
    },
    {
      name: "chromium",
      use: {
        ...devices["Desktop Chrome"],
        // Use auth state from setup
        storageState: path.join(__dirname, ".auth", "user.json"),
      },
      dependencies: ["setup"],
    },
  ]
});
