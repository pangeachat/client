import path from "path";
import { expect, test } from "./fixtures";

/**
 * Authentication setup - logs in once and saves auth state for all tests.
 *
 * Uses environment variables from .env:
 * - STAGING_TEST_EMAIL: Matrix username or email
 * - STAGING_TEST_PASSWORD: Password
 */

const authFile = path.join(__dirname, ".auth", "user.json");

test("authenticate", async ({ page }) => {
  // Click "Login to my account" button
  await page.getByRole("button", { name: "Login to my account" }).click();

  // Click "Email" login method
  await page.getByRole("button", { name: "Email" }).click();

  // Fill username/email — click to focus first, Flutter needs explicit focus
  const usernameField = page.getByRole("textbox", {
    name: "Username or email",
  });
  await usernameField.click();
  await usernameField.fill(process.env.STAGING_TEST_EMAIL!);

  // Small delay for Flutter to commit the input state
  await page.waitForTimeout(500);

  // Fill password
  const passwordField = page.getByRole("textbox", { name: "Password" });
  await passwordField.click();
  await passwordField.fill(process.env.STAGING_TEST_PASSWORD!);

  // Wait for Login button to become enabled
  await page.waitForTimeout(500);

  // Click login button
  await page.getByRole("button", { name: "Login" }).click();

  // Wait for chat list to load (URL should contain /rooms)
  // Login involves a Matrix server round-trip, so give it ample time
  await expect(page).toHaveURL(/\/rooms/, { timeout: 30000 });

  // Save authentication state (indexedDB: true captures Flutter/Matrix
  // session tokens stored in IndexedDB, not just cookies + localStorage)
  await page.context().storageState({ path: authFile, indexedDB: true });
});
