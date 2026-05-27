import fs from "fs";
import path from "path";
import { expect, test } from "../fixtures";

/**
 * Settings flow test
 *
 * Triggers:
 * - lib/pages/settings/**
 * - lib/pangea/learning_settings/**
 * - lib/pangea/subscription/**
 */

// Prerequisites:
// L1 is english
test.describe("Settings", () => {

  test("should be able to navigate settings", async ({
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
