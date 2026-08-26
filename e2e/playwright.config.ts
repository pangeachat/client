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
    {
      // A real 1:1 call needs TWO parties, each with their OWN voice.
      //
      // One machine has one microphone, so a live two-party call can never be
      // tested by hand here: both sides would capture the same room and
      // per-speaker attribution -- the whole point of the transcript -- is
      // exactly what cannot be checked. Chromium's fake capture solves it:
      // each browser context is handed its own WAV file as its microphone, so
      // the two halves carry provably different speech.
      //
      // No storageState: this project signs both accounts in itself, because
      // the shared one is a single account and a call needs two.
      name: "calls",
      testMatch: /calls\/.*\.spec\.ts/,
      use: {
        ...devices["Desktop Chrome"],
        permissions: ["microphone"],
        launchOptions: {
          args: [
            "--use-fake-ui-for-media-stream",
            "--use-fake-device-for-media-stream",
            "--autoplay-policy=no-user-gesture-required",
          ],
        },
      },
    },
  ]
});
