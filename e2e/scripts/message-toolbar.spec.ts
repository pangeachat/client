import fs from "fs";
import path from "path";
import { expect, test } from "../fixtures";

/**
 * Message toolbar test
 *
 * Triggers:
 * - lib/pangea/toolbar/**
 * - lib/pangea/text_to_speech/**
 * - lib/pangea/token_info_feedback/**
 * - lib/pangea/phonetic_transcription/**
 */

// playwright todo: update assumptions
// Context assumptions: 
// There is at least 1 room in chat list
// Account languages are english > cantonese
// There is 1 english message and 1 cantonese message in the room
test.describe("Message Toolbar", () => {

  test("toolbar works and appropriate buttons are enabled", async ({
    page,
  }) => {

    // Use intl key values as object names
    const filePath = path.resolve(__dirname, '../../lib/l10n/intl_en.arb');
    const fileContent = fs.readFileSync(filePath, 'utf-8');
    const intl = JSON.parse(fileContent);

    // Open chat
    // playwright todo: move away from hardcoded name?
    await page.getByRole("button", { name: "playwright" }).click();

    // Check that appropriate buttons are enabled on toolbar for message in L1
    // Select L1 message 

    // getByRole and getByText don't seem to work
    // so this clicks a specific spot on the screen 
    // playwright todo: find better method of selecting message
    // May require adding semantic label to messages
    const viewport = page.viewportSize();
    if (viewport) {
      await page.mouse.click(viewport.width - 122, viewport.height - 122);
    }

    // Check that toolbar buttons are shown
    await expect(page.getByRole("button", { name: intl.playAudio, exact: true })).toBeVisible();
    await expect(page.getByRole("button", { name: intl.translationTooltip, exact: true })).toBeVisible();
    await expect(page.getByRole("button", { name: intl.practice, exact: true })).toBeVisible();
    await expect(page.getByRole("button", { name: intl.emojiView, exact: true })).toBeVisible();
    await expect(page.getByRole("button", { name: intl.more, exact: true })).toBeVisible();

    // Playwright todo: Once load testing is set up, test button behavior

  });
});
