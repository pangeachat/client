import fs from "fs";
import path from "path";
import { expect, test } from "../fixtures";

/**
 * Course and chat navigation test
 *
 * Triggers:
 * - lib/pangea/course_creation/**
 * - lib/pangea/course_plan/**
 * - lib/pages/chat_list/**
 * - lib/pangea/chat_list/**
 * - lib/pangea/common/controllers/pangea_controller.dart
 * - lib/config/routes.dart
 */

test.describe("Course and chat navigation", () => {

  test("Should be able to navigate chat list and add course pages", async ({
    page,
  }) => {

    // Use intl key values as object names
    const filePath = path.resolve(__dirname, '../../lib/l10n/intl_en.arb');
    const fileContent = fs.readFileSync(filePath, 'utf-8');
    const intl = JSON.parse(fileContent);

    // Set L2 to spanish, if it isn't already
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

    await page.getByRole("button", { name: intl.addCourse, exact: true }).click();
    await page.getByRole("button", { name: intl.addCourse, exact: true }).click();

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
    if (await page.getByRole("button", { name: intl.goToExistingCourse, exact: true }).isVisible()) {
      await page.getByRole("button", { name: intl.createCourse, exact: true }).click();
    }
    await page.getByRole("button", { name: intl.createCourse, exact: true }).click();
    await expect(page.getByRole("button", { name: intl.playWithAI, exact: true })).toBeVisible();

    // Navigate to home page and check that it works
    // Then return to normal chat list page
    await page.getByRole("button", { name: intl.home, exact: true }).click();
    await expect(page.getByText(intl.profile, { exact: true })).toBeVisible();
    await page.getByRole("button", { name: intl.allChats, exact: true }).click();

    // Find all cousin buttons of addCourse button
    // Then filter out non-course buttons
    var nonCourse = [intl.addCourse, intl.allChats, intl.learningAnalytics, intl.home];
    var nonCourseFilter = new RegExp(`\\b(${nonCourse.join('|')})\\b`);
    var courses = page.getByRole("button", { name: intl.addCourse }).locator('..').locator('..').getByRole("button").filter({ hasNotText: nonCourseFilter });

    // Navigate to first course in course list
    await courses.first().click();

    // If notification request button appears, close it
    if (await page.getByRole("button", { name: intl.skipForNow, exact: true }).isVisible()) {
      await page.getByRole("button", { name: intl.skipForNow, exact: true }).click();
    }

    // Delete joined course to restore state for future tests
    await page.getByRole("button", { name: intl.more, exact: true }).click();
    var leave = page.getByRole("button", { name: intl.leave });
    await leave.scrollIntoViewIfNeeded();
    await leave.click();
    await page.getByRole("button", { name: intl.leave }).click();
  });
});
