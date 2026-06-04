import fs from "fs";
import path from "path";
import { expect, test } from "../fixtures";

/**
 * Analytics flow test
 *
 * Triggers:
 * - lib/pangea/analytics_page/**
 * - lib/pangea/analytics_practice/**
 * - lib/pangea/analytics_misc/**
 */

test.describe("Analytics", () => {

  test("should be able to navigate and use analytics", async ({
    page,
  }) => {

    // Use intl key values as object names
    const filePath = path.resolve(__dirname, '../../lib/l10n/intl_en.arb');
    const fileContent = fs.readFileSync(filePath, 'utf-8');
    const intl = JSON.parse(fileContent);

    // Set L2 to spanish, if not already
    if (await page.getByRole("button", { name: "EN ES" }).isHidden()) {
      await page.getByRole("button", { name: intl.learningSettings }).click();
      await page.getByRole("button", { name: intl.iWantToLearn }).click();
      var langSearch = page.getByRole("textbox", { name: intl.searchLanguagesHint });
      await langSearch.click();
      await langSearch.fill(intl.esDisplayName);
      await page.getByRole("button", { name: intl.esMXDisplayName }).click();
      await page.getByRole("button", { name: intl.saveChanges }).click();
      await expect(page.getByRole("button", { name: "EN ES" })).toBeVisible({ timeout: 60000 });
    }

    // Go to vocab analytics
    await page.getByRole("button", { name: intl.learningAnalytics }).click();
    await page.getByRole("button", { name: intl.learningAnalytics }).click();
    await expect(page.getByRole("button", { name: intl.download })).toBeVisible();

    // Go to saved activities
    await page.getByRole("button", { name: intl.activities }).click();
    await expect(page.getByRole("button", { name: intl.download })).toBeHidden();

    // Go to grammar practice
    await page.getByRole("button", { name: intl.grammar }).click();
    await expect(page.getByRole("button", { name: intl.download })).toBeVisible();

    // Go to level analytics
    await page.getByRole("button", { name: intl.level }).click();
    await expect(page.getByRole("group", { name: intl.levelInfoTooltip })).toBeVisible();
  });
});