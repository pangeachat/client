import fs from "fs";
import path from "path";
import { expect, test } from "../fixtures";

/**
 * Logout flow test
 *
 * Triggers:
 * - lib/pages/settings/**
 * - lib/pangea/login/**
 * - lib/widgets/matrix.dart
 */

test.describe("Logout", () => {

  test("should be able to log out of account", async ({
    page,
  }) => {

    // Use intl key values as object names
    const filePath = path.resolve(__dirname, '../../lib/l10n/intl_en.arb');
    const fileContent = fs.readFileSync(filePath, 'utf-8');
    const intl = JSON.parse(fileContent);

    // Open settings
    await page.getByRole("button", { name: intl.settings, exact: true }).click();
    await page.getByRole("button", { name: intl.settings, exact: true }).click();

    // Log out
    await page.getByRole("button", { name: intl.settings, exact: true }).click();
    await page.getByRole("button", { name: intl.logout }).click();
    await page.getByRole("button", { name: intl.logout }).click();
    await expect(page.getByRole("button", {name: intl.loginToAccount })).toBeVisible();
  });
});
