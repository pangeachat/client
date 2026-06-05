import fs from "fs";
import path from "path";
import { expect, test } from "../fixtures";

/**
 * Settings flow test
 *
 * Triggers:
 * - lib/pages/settings/**
 * - lib/pangea/learning_settings/**
 * - lib/pangea/subscription/**
 */

test.describe("Settings", () => {

  test("should be able to navigate settings", async ({
    page,
  }) => {

    // Use intl key values as object names
    const filePath = path.resolve(__dirname, '../../lib/l10n/intl_en.arb');
    const fileContent = fs.readFileSync(filePath, 'utf-8');
    const intl = JSON.parse(fileContent);

    // Open settings
    await page.getByRole("button", { name: intl.settings, exact: true }).click();
    await page.getByRole("button", { name: intl.settings, exact: true }).click();

    // Learning settings
    await page.getByRole("button", { name: intl.learningSettings }).click();
    await expect(page.getByRole("button", { name: intl.profile, exact: true })).toBeVisible();

    // Style
    await page.getByRole("button", { name: intl.changeTheme }).click();
    await expect(page.getByRole("radio", { name: intl.lightTheme, exact: true })).toBeVisible();

    // Devices
    await page.getByRole("button", { name: intl.devices }).click();
    await expect(page.getByRole("button", { name: intl.removeAllOtherDevices })).toBeVisible();

    // Chat
    await page.getByRole("button", { name: intl.chat, exact: true }).click();
    await expect(page.getByRole("switch", { name: intl.hideRedactedMessages })).toBeVisible();

    // Subscription management
    await page.getByRole("button", { name: intl.subscriptionManagement }).click();
    await expect(page.getByRole("heading", { name: intl.subscriptionManagement, exact: true })).toBeVisible();

    // Security
    await page.getByRole("button", { name: intl.security }).click();
    await page.getByRole("button", { name: intl.changeEmail }).click();
    await expect(page.getByRole("button", { name: intl.addEmail })).toBeVisible();
    await page.getByRole("button", { name: intl.security }).click();
    await page.getByRole("button", { name: intl.changePassword }).click();
    await expect(page.getByRole("textbox", { name: intl.pleaseEnterYourCurrentPassword })).toBeVisible();

    // Support
    await expect(page.getByRole("button", { name: intl.chatWithSupport })).toBeEnabled();

    // Notifications
    await page.getByRole("button", { name: intl.notifications }).click();

    await expect(page.getByRole("button", { name: intl.gotIt, exact: true }).or(page.getByRole("group", { name: intl.notificationRuleMaster, exact: true }))).toBeVisible();
  });
});
