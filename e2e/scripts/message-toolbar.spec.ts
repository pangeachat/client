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

    // Test toolbar mode behaviors
    // Select L2 message

    // Select message using edit time as target
    // playwright todo: edit targeting method
    // May require adding semantic label to messages
    page.getByRole("group", { name: "1:39" }).click();

    await expect(page.getByRole("button", { name: intl.more, exact: true })).toBeVisible();

    // Audio mode should be enabled 
    await expect(page.getByRole("button", { name: intl.playAudio, exact: true })).toBeEnabled();

    // Translation mode should show translated text
    // playwright todo: don't hardcode translation?
    await page.getByRole("button", { name: intl.translationTooltip, exact: true }).click();
    await expect(page.getByText("Hello")).toBeVisible();

    // Emoji mode should be enabled
    await expect(page.getByRole("button", { name: intl.emojiView, exact: true })).toBeEnabled();

    // Practice mode should show practice mode buttons
    await page.getByRole("button", { name: intl.practice, exact: true }).click();

    // Pressing practice mode buttons works
    // Assumes all modes are available for the message, 
    // and that instructions are shown
    await page.getByRole("button", { name: intl.listen, exact: true }).click();
    await expect(page.getByText(intl.chooseWordAudioInstructionsBody)).toBeVisible();

    await page.getByRole("button", { name: intl.grammar, exact: true }).click();
    await expect(page.getByText(intl.chooseMorphsInstructionsBody)).toBeVisible();

    await page.getByRole("button", { name: intl.meaning, exact: true }).click();
    await expect(page.getByText(intl.chooseLemmaMeaningInstructionsBody)).toBeVisible();

    await page.getByRole("button", { name: intl.image, exact: true }).click();
    await expect(page.getByText(intl.chooseEmojiInstructionsBody)).toBeVisible();
  });
});
