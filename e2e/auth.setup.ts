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

  // If button can't be found, requirements of test may not be met.
  await expect(page.getByRole("button", { name: intl.loginToAccount }), { message: 'Ensure the system language is english, and the account is not already authenticated.' }).toBeEnabled();

  await page.getByRole("button", { name: intl.loginToAccount }).click();

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

  // Login involves a Matrix server round-trip, so give it ample time. On
  // world_v2 a successful login lands on the world map (PRoutes.world = '/'),
  // not the retired v1 '#/rooms'. Wait until the app leaves the login flow,
  // which means the Matrix session is established.
  await expect(page).not.toHaveURL(/\/login/, { timeout: 120000 });
  // Let the post-login navigation and the IndexedDB session write settle before
  // capturing storage state.
  await page.waitForTimeout(3000);

  // Save authentication state (indexedDB: true captures Flutter/Matrix
  // session tokens stored in IndexedDB, not just cookies + localStorage)
  await page.context().storageState({ path: authFile, indexedDB: true });
});
