import { defineConfig, devices } from "@playwright/test";
import fs from "fs";
import path from "path";

// Load env vars from client/.env 
const envPath = path.resolve(__dirname, "../..", ".env");
if (fs.existsSync(envPath)) {
  for (const line of fs.readFileSync(envPath, "utf-8").split("\n")) {
    const match = line.match(/^\s*([\w]+)\s*=\s*['"]?(.+?)['"]?\s*$/);
    if (match && !process.env[match[1]]) process.env[match[1]] = match[2];
  }
}

// Load env vars from client/assets/.env 
const assetsEnvPath = path.resolve(__dirname, "../..", "assets/.env");
if (fs.existsSync(assetsEnvPath)) {
  for (const line of fs.readFileSync(assetsEnvPath, "utf-8").split("\n")) {
    const match = line.match(/^\s*([\w]+)\s*=\s*['"]?(.+?)['"]?\s*$/);
    if (match && !process.env[match[1]]) process.env[match[1]] = match[2];
  }
}

/**
 * Playwright config for Pangea Chat playwright API tests.
 * See https://playwright.dev/docs/api-testing.
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
    /* Collect trace when retrying the failed test. See https://playwright.dev/docs/trace-viewer */
    trace: "on-first-retry",
  },

  /* Configure projects for API testing */
  projects: [
    {
      name: "setup",
      testMatch: /.*\.setup\.ts/,
      testDir: "./",
    },
    {
      name: "api",
      testDir: "./scripts",
      use: {
        baseURL: 'https://app.staging.pangea.chat',
        // Use auth state from setup
        storageState: path.join(__dirname, ".auth", "api-token.json"),
        extraHTTPHeaders: {
          "user_cefr": "A1",
          "user_gender":	"other",
          "user_l1":	"en",
        },
      },
      dependencies: ["setup"],
    },
  ],
});