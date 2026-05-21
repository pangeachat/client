import fs from "fs";
import path from "path";
import { expect, test } from "./fixtures";

/**
 * Authentication setup - logs in once and saves auth state for all tests.
 *
 * Uses environment variables from .env (local) or AWS Secrets Manager (CI):
 * - TEST_MATRIX_USERNAME: Matrix username (localpart, no @ or domain)
 * - TEST_MATRIX_PASSWORD: Password
 */

const authFile = path.join(__dirname, ".auth", "user.json");

test("authenticate", async ({ page }) => {  
  // Use intl key values as object names
  const filePath = path.resolve(__dirname, '../lib/l10n/intl_en.arb');
  const fileContent = fs.readFileSync(filePath, 'utf-8');
  const intl = JSON.parse(fileContent);

  // Avoid test timing out on login 
  test.setTimeout(120000); 

  console.log("Ensure test device has English as a system language, or button selection won't work");

  // Click "Login to my account" button
  try {
    await page.getByRole("button", { name: intl.loginToAccount }).click();
  } catch (error) {
    // If button was not found, the account may already be authenticated, 
    // or the language is not english
    console.error('Locator timeout exceeded:', error.message);
    console.log('Check that english is selected, and the account is not already authenticated.')
  }

  // Click "Email" login method
  await page.getByRole("button", { name: intl.email }).click();

  // Fill username/email — click to focus first, Flutter needs explicit focus
  const usernameField = page.getByRole("textbox", {
    name: intl.usernameOrEmail,
  });
  await usernameField.click();
  await usernameField.fill(process.env.TEST_MATRIX_USERNAME!);

  // Fill password
  const passwordField = page.getByRole("textbox", { name: intl.password });
  await passwordField.click();
  await page.waitForTimeout(500);
  await passwordField.fill(process.env.TEST_MATRIX_PASSWORD!);

  // Click login button once it's enabled
  const loginButton = page.getByRole("button", { name: intl.login });
  await expect(loginButton).toBeEnabled();
  await loginButton.click();

  // Wait for chat list to load (URL should contain /rooms)
  // Login involves a Matrix server round-trip, so give it ample time
  await expect(page).toHaveURL("#/rooms", { timeout: 120000 });

  // Save authentication state (indexedDB: true captures Flutter/Matrix
  // session tokens stored in IndexedDB, not just cookies + localStorage)
  await page.context().storageState({ path: authFile, indexedDB: true });
});
