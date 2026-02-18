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
  test.use({ storageState: { cookies: [], origins: [] } }); // Don't use saved auth for login test

  test("should display landing page and login successfully", async ({
    page,
  }) => {
    // Fixture already navigated to '/' and enabled Flutter semantics tree

    // Verify landing page elements are visible
    await expect(page.getByRole("button", { name: "Start" })).toBeVisible();
    await expect(
      page.getByRole("button", { name: "Login to my account" }),
    ).toBeVisible();

    // Click "Login to my account"
    await page.getByRole("button", { name: "Login to my account" }).click();

    // Click "Email" login method
    await page.getByRole("button", { name: "Email" }).click();

    // Fill credentials — click to focus first, Flutter needs explicit focus
    const usernameField = page.getByRole("textbox", {
      name: "Username or email",
    });
    await usernameField.click();
    await usernameField.fill(process.env.STAGING_TEST_EMAIL!);

    await page.waitForTimeout(500);

    const passwordField = page.getByRole("textbox", { name: "Password" });
    await passwordField.click();
    await passwordField.fill(process.env.STAGING_TEST_PASSWORD!);

    await page.waitForTimeout(500);

    // Click login
    await page.getByRole("button", { name: "Login" }).click();

    // Wait for chat list to load
    await expect(page).toHaveURL(/\/rooms/, { timeout: 30000 });

    // Verify chat list UI is visible
    await expect(page.getByRole("button", { name: "Home" })).toBeVisible();
    await expect(page.getByRole("button", { name: "Settings" })).toBeVisible();
  });
});
