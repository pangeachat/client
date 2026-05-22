import fs from "fs";
import path from "path";
import { expect, test } from "../fixtures";

/**
 * Chat list navigation test
 *
 * Triggers:
 * - lib/pages/chat_list/**
 * - lib/pangea/chat_list/**
 * - lib/pangea/common/controllers/pangea_controller.dart
 * - lib/config/routes.dart
 */

// Prerequisites:
// L1 is english
// There is at least 1 joined course
test.describe("Chat list navigation", () => {

  test("should be able to move to, from, and within the chat list page", async ({
    page,
  }) => {

    // Use intl key values as object names
    const filePath = path.resolve(__dirname, '../../lib/l10n/intl_en.arb');
    const fileContent = fs.readFileSync(filePath, 'utf-8');
    const intl = JSON.parse(fileContent);

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

    // If no courses are found, test requirements not met
    await expect(await courses.count(), { message: 'Account must have 1+ joined courses' }).toBeGreaterThan(0);

    // Navigate to first course in course list
    await courses.first().click();

    // If notification request button appears, close it
    if (await page.getByRole("button", { name: intl.skipForNow, exact: true }).isVisible()) {
      await page.getByRole("button", { name: intl.skipForNow, exact: true }).click();
    }

    // Check that course page shows properly
    // playwright todo: If using this script for mobile testing, 
    // will need to use elements in course chat list to check instead
    await expect(page.getByRole("button", { name: intl.coursePlan })).toBeVisible();

    // Return to normal chat list page
    await page.getByRole("button", { name: intl.allChats, exact: true }).click();

    // Show learning settings popup
    await page.getByRole("button", { name: intl.learningSettings }).click();
    await expect(page.getByText(intl.profile, { exact: true })).toBeVisible();
  });
});
