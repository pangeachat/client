import fs from "fs";
import path from "path";
import { expect, test } from "../fixtures";

/**
 * Apple and Google sign-in start without the "Sign-in site unreachable"
 * dialog on an open network.
 *
 * Before either sign-in, the web app asks the provider's sign-in host
 * whether the network lets it through (filtered-network.instructions.md).
 * A check URL that a browser can never reach shows that dialog to every
 * user: the Apple one redirected to plain http, which an https page refuses
 * (#9441). Only an https build shows it; on http://localhost the browser
 * follows the redirect, so run this against a deployed build.
 *
 * Triggers:
 * - lib/routes/home/p_sso_button.dart
 * - lib/features/network_filter/**
 */

const intl = JSON.parse(
  fs.readFileSync(
    path.resolve(__dirname, "../../lib/l10n/intl_en.arb"),
    "utf-8",
  ),
);

test.describe("Sign-in provider network check", () => {
  test.use({ storageState: { cookies: [], origins: [] } });

  for (const provider of ["withApple", "withGoogle"]) {
    test(`"${intl[provider]}" opens the provider's sign-in`, async ({
      page,
    }) => {
      await page.getByRole("button", { name: intl.getStarted }).click();

      // On desktop the sign-in opens in a new window, and only after the
      // network check passes.
      const signInWindow = page
        .waitForEvent("popup", { timeout: 15000 })
        .catch(() => null);
      await page.getByRole("button", { name: intl[provider] }).click();

      const opened = await signInWindow;
      await expect(
        page.getByText(intl.ssoNetworkBlockedTitle),
        "the network check reported an open network as filtered",
      ).toHaveCount(0);
      expect(opened, "the sign-in window never opened").not.toBeNull();
      await opened?.close();
    });
  }
});
