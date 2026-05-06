import fs from "fs";
import path from "path";
import { expect, test } from "../fixtures";

/**
 * Open chat test
 *
 * Triggers:
 * - lib/pages/chat/**
 * - lib/pages/chat_list/chat_list_item.dart
 * - lib/pangea/chat_list/**
 */


// playwright todo: update assumptions
// Context assumptions:
// There is a chat named 'playwright' in the chat list
test.describe("Message Toolbar", () => {

  test("should be able to send a message", async ({
    page,
  }) => {

    // Use intl key values as object names
    const filePath = path.resolve(__dirname, '../../lib/l10n/intl_en.arb');
    const fileContent = fs.readFileSync(filePath, 'utf-8');
    const intl = JSON.parse(fileContent);

    // Select chat named 'playwright'
    // playwright todo: move away from hardcoded name?
    await page.getByRole("button", { name: "playwright" }).click();

    // Ensure chat was opened 
    await expect(page.getByRole("button", { name: intl.chatDetails })).toBeVisible();
  });
});
