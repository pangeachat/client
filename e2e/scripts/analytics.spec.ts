import fs from "fs";
import path from "path";
import { expect, test } from "../fixtures";

/**
 * Analytics flow test
 *
 * Triggers:
 * - 
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

    await page.getByRole("button", { name: intl.vocab }).click();

    // If analytics room does not already have enough lemmas
    // for practice to be enabled, send a message to get them
    if (await page.getByRole("button", { name: intl.practiceVocab }).isDisabled()) {
        // Create a direct message
        await page.getByRole("button", { name: intl.allChats }).click();
        await page.getByRole("button", { name: intl.directMessage, exact: true }).click();
        const dmSearch = page.getByRole("textbox", { name: intl.searchForUsers });
        await dmSearch.click();
        await dmSearch.fill("test");
        await page.getByRole("button", { name: "pangea.chat" }).first().click();
        if (await page.getByRole("button", { name: intl.startConversation, exact: true }).isVisible()) {
            await page.getByRole("button", { name: intl.startConversation, exact: true }).click();
        } else {
            await page.getByRole("button", { name: intl.sendAMessage, exact: true }).click();
        }

        // Send message with Spanish lemmas to add to analytics
        var message = "cómo estar gusto nombre ayudar conocer favor llamar placer poder qué";
        await page.getByRole("textbox", { name: intl.writeAMessageLangCodes.substring(0, 7) }).fill(message);

        // Send message
        await page.getByRole("button", { name: intl.send }).click();

        await page.getByRole("button", { name: intl.vocab }).click();
    }

    await page.getByRole("button", { name: intl.practiceVocab }).click()

    // Delete DM to restore state for future tests
    await page.getByRole("button", { name: intl.allChats }).click();
    await page.getByRole("button", { name: intl.allChats }).click();
    await page.getByRole("button", { name: intl.moreOptions }).first().click();
    await page.getByRole("button", { name: intl.chatDetails }).click();
    await page.getByRole("button", { name: "Show menu" }).click();
    await page.getByRole("menuitem", { name: intl.leave }).click();
    await page.getByRole("button", { name: intl.leave }).click();
  });
});