import fs from "fs";
import path from "path";
import { expect, test } from "../fixtures";

/**
 * Course discovery test
 *
 * Triggers:
 * - lib/pangea/course_creation/**
 * - lib/pangea/course_plan/**
 */

// Prerequisites:
// User languages are english -> spanish
// playwright todo
test.describe("Course discovery", () => {

  test("should be able to view pages for finding, joining, and making courses", async ({
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

    // Select a public course 
    await page.getByRole("button", { name: intl.knock, exact: true }).first().click();
    await expect(page.getByText(intl.joinWithClassCode, { exact: true })).toBeVisible();
    // Return to previous page
    await page.getByRole("button", { name: intl.addCourse, exact: true }).click();

    // Select join with code button
    await page.getByRole("button", { name: intl.joinWithCode, exact: true }).click();
    await expect(page.getByText(intl.joinWithCode, { exact: true })).toBeVisible();
    // Return to previous page
    await page.getByRole("button", { name: intl.addCourse, exact: true }).click();

    // Create a course
    await page.getByRole("button", { name: intl.newCourse, exact: true }).click();
    await page.getByRole("button", { name: intl.numModules.substring(5) }).first().click();
    await page.getByRole("button", { name: intl.createCourse, exact: true }).click();
    if (await page.getByRole("button", { name: intl.createCourse, exact: true }).isVisible()) {
      await page.getByRole("button", { name: intl.createCourse, exact: true }).click();
    }
    await expect(page.getByRole("button", { name: intl.playWithAI, exact: true })).toBeVisible();
  });
});
