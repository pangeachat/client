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

// playwright todo: update assumptions
// Context assumptions:
// There is a chat named 'playwright' in the chat list
test.describe("Message Toolbar", () => {

  test("should be move to, from, and within the chat list page", async ({
    page,
  }) => {

    // Use intl key values as object names
    const filePath = path.resolve(__dirname, '../../lib/l10n/intl_en.arb');
    const fileContent = fs.readFileSync(filePath, 'utf-8');
    const intl = JSON.parse(fileContent);

    // Navigate to home page
    await page.getByRole("button", { name: intl.home, exact: true }).click();
    await expect(page.getByText(intl.profile, { exact: true })).toBeVisible();
    await page.getByRole("button", { name: intl.allChats, exact: true }).click();

    // Navigate to/from a course
    // playwright todo: hardcoded course name
    await page.getByRole("button", { name: "Global Connections" }).click();
    await page.getByRole("button", { name: intl.skipForNow, exact: true }).click();
    await expect(page.getByRole("button", { name: intl.introChatTitle })).toBeVisible();
    await page.getByRole("button", { name: intl.allChats, exact: true }).click();

    // Show learning settings popup
    await page.getByRole("button", { name: intl.learningSettings }).click();
    await expect(page.getByText(intl.profile, { exact: true })).toBeVisible();
  });
});
