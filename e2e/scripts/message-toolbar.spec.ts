import fs from "fs";
import path from "path";
import { expect, test } from "../fixtures";

/**
 * Message toolbar test
 *
 * Triggers:
 * - lib/pages/new_private_chat/**
 * - lib/pangea/chat_list/**
 * - lib/pages/chat/**
 * - lib/pages/chat_list/chat_list_item.dart
 * - lib/pangea/chat_list/**
 * - lib/pages/chat/chat_input_row.dart
 * - lib/pages/chat/input_bar.dart
 * - lib/pangea/choreographer/**
 * - lib/pangea/events/**
 * - lib/pangea/toolbar/**
 * - lib/pangea/text_to_speech/**
 * - lib/pangea/token_info_feedback/**
 * - lib/pangea/phonetic_transcription/**
 */

test.describe("Message Toolbar", () => {

  test("toolbar works and appropriate buttons are enabled", async ({
    page,
  }) => {
    // This flow is long - keep it from timing out
    test.setTimeout(60000); 

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

    // Create a direct message
    await page.getByRole("button", { name: intl.directMessage, exact: true }).click();
    const dmSearch = page.getByRole("textbox", { name: intl.searchForUsers });
    await dmSearch.click();
    await dmSearch.fill("test");
    await page.getByRole("button", { name: "pangea.chat" }).first().click();

    // Either start conversation or send a message, 
    // depending on whether DM already exists
    if (await page.getByRole("button", { name: intl.startConversation, exact: true }).isVisible()) {
      await page.getByRole("button", { name: intl.startConversation, exact: true }).click();
    } else {
      await page.getByRole("button", { name: intl.sendAMessage, exact: true }).click();
    }

    await page.getByRole("button", { name: intl.allChats }).click();
    await page.getByRole("button", { name: intl.allChats }).click();

    // Open first chat in chat list
    await page.getByRole("button", { name: intl.moreOptions }).first().click();

    // Check that input bar is shown and selectable
    await expect(page.getByRole("textbox", { name: intl.writeAMessageLangCodes.substring(0, 7) }), { message: 'Ensure messages are enabled.' }).toBeEditable();

    // Input bar is automatically selected on chat open
    // Type Spanish message in input bar
    var message = "yoo soy";
    await page.getByRole("textbox", { name: intl.writeAMessageLangCodes.substring(0, 7) }).fill(message);

    // Send message
    await page.getByRole("button", { name: intl.send }).click();

    // Test toolbar mode behaviors
    // Select sent message
    // Message needs to have space in middle so that
    // a word card isn't opened on selection
    page.getByRole("group", { name: message }).first().click();

    // Expect 'More' button to be shown
    await expect(page.getByRole("button", { name: intl.more, exact: true })).toBeVisible();

    // Audio mode should be enabled 
    await expect(page.getByRole("button", { name: intl.playAudio, exact: true })).toBeEnabled();

    // Translation doesn't work when mocking,
    // so expect translation error
    await page.getByRole("button", { name: intl.translationTooltip, exact: true }).click();
    await expect(page.getByText(intl.translationError)).toBeVisible();

    // Emoji mode should be enabled
    await expect(page.getByRole("button", { name: intl.emojiView, exact: true })).toBeEnabled();

    // Practice mode should show practice mode buttons
    await page.getByRole("button", { name: intl.practice, exact: true }).click();

    // Pressing practice mode buttons show their respective instructions 
    await page.getByRole("button", { name: intl.listen, exact: true }).click();
    await expect(page.getByText(intl.chooseWordAudioInstructionsBody)).toBeVisible();

    await page.getByRole("button", { name: intl.grammar, exact: true }).last().click();
    await expect(page.getByText(intl.chooseMorphsInstructionsBody)).toBeVisible();

    await page.getByRole("button", { name: intl.meaning, exact: true }).click();
    await expect(page.getByText(intl.chooseLemmaMeaningInstructionsBody)).toBeVisible();

    await page.getByRole("button", { name: intl.image, exact: true }).click();
    await expect(page.getByText(intl.chooseEmojiInstructionsBody)).toBeVisible();

    // Delete DM to restore state for future tests
    await page.getByRole("button", { name: intl.moreOptions }).first().click();
    await page.getByRole("button", { name: intl.chatDetails }).click();
    await page.getByRole("button", { name: "Show menu" }).click();
    await page.getByRole("menuitem", { name: intl.leave }).click();
  });
});
