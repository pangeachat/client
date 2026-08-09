import fs from "fs";
import path from "path";
import { expect, test } from "../fixtures";

/**
 * Login and logout flow test
 *
 * Triggers:
 * - lib/pangea/login/**
 * - lib/pages/login/**
 * - lib/config/routes.dart
 * - lib/widgets/matrix.dart
 * - lib/pages/settings/**
 */

test.describe("Should be able to Login and logout", () => {
  // Don't use saved auth for login test
  test.use({ storageState: { cookies: [], origins: [] } }); 

  test("should display landing page and login successfully", async ({
    page,
  }) => {
    // Use intl key values as object names
    const filePath = path.resolve(__dirname, '../../lib/l10n/intl_en.arb');
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

    // On world_v2 a successful login leaves the login flow and lands on the
    // world map (PRoutes.world = '/'), not the retired v1 '#/rooms'. Login is a
    // Matrix round-trip, so allow ample time.
    await expect(page).not.toHaveURL(/\/login/, { timeout: 120000 });
    await page.waitForTimeout(3000);

    // Open the settings panel (world_v2: ?right=settings) and log out.
    await page.goto("/#/?right=settings");
    await page.getByRole("button", { name: intl.logout }).click();
    await page.getByRole("button", { name: intl.logout }).click();
    await expect(page.getByRole("button", { name: intl.loginToAccount })).toBeVisible({ timeout: 30000 });
  });
});
