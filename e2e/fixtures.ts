import { test as base, expect } from "@playwright/test";

/**
 * Shared test fixture for Pangea Chat E2E tests.
 *
 * Flutter renders to <canvas>, so Playwright can only interact with the
 * semantics tree. This fixture enables Flutter's accessibility tree on each page load.
 */
export const test = base.extend({
  page: async ({ page }, use) => {
    // Navigate to the app and wait for Flutter to render
    await page.goto("/");

    // Enable Flutter semantics tree.
    // Flutter positions flt-semantics-placeholder off-screen, so Playwright's
    // click() cannot reach it even with force:true. Use dispatchEvent instead.
    await page
      .getByRole("button", { name: "Enable accessibility" })
      .dispatchEvent("click", { timeout: 15000 });

    // Wait for semantics tree to populate after enabling
    await page.waitForTimeout(3000);

    await use(page);
  },
});

export { expect };
