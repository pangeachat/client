import fs from "fs";
import path from "path";
import { expect, test } from "../fixtures";

/**
 * Send message test
 *
 * Triggers:
 * - lib/pages/chat/chat_input_row.dart
 * - lib/pages/chat/input_bar.dart
 * - lib/pangea/choreographer/**
 * - lib/pangea/events/**
 */


// playwright todo: update assumptions
// Context assumptions:
// There is at least 1 room in chat list
// Account can send messages in selected room
test.describe("Message Toolbar", () => {

  test("should be able to send a message", async ({
    page,
  }) => {

    // Use intl key values as object names
    const filePath = path.resolve(__dirname, '../../lib/l10n/intl_en.arb');
    const fileContent = fs.readFileSync(filePath, 'utf-8');
    const intl = JSON.parse(fileContent);

    // Test steps are conducted sequentially

    // Open chat
    // playwright todo: move away from hardcoded name?
    await page.getByRole("button", { name: "playwright" }).click();

    // Input bar is automatically selected on chat open

    // Type Cantonese message in input bar 
    await page.getByRole("textbox", { name: intl.writeAMessageLangCodes.substring(0, 7) }).fill("néih hóu");

    // Send message
    await page.getByRole("button", { name: intl.send }).click();
    
    // Ensure message was sent properly
    await expect(page.getByText("néih hóu")).toBeEnabled();
  });
});
