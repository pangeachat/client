import fs from "fs";
import path from "path";
import { expect, test } from "../fixtures";

/**
 * Login flow test
 *
 * Triggers:
 * - lib/pangea/login/**
 * - lib/pages/login/**
 * - lib/config/routes.dart
 * - lib/widgets/matrix.dart
 */

test.describe("Login", () => {
  // Don't use saved auth for login test
  test.use({ storageState: { cookies: [], origins: [] } }); 

  test("should display landing page and login successfully", async ({
    page,
  }) => {
    // Use intl key values as object names
    const filePath = path.resolve(__dirname, '../../lib/l10n/intl_en.arb');
    const fileContent = fs.readFileSync(filePath, 'utf-8');
    const intl = JSON.parse(fileContent);

    // Add 'mock: true' field to requests
    await page.route('**/choreo/*', (route) => {
      const headers = {
        ...route.request().headers(),
        'mock': 'true',
      };

      route.continue({
        headers: headers
      });
    });

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

    // Wait for chat list to load (URL should contain /rooms)
    // Login involves a Matrix server round-trip, so give it ample time
    await expect(page).toHaveURL("#/rooms", { timeout: 120000 });
  });
});
