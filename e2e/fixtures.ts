import { test as base, expect } from "@playwright/test";

/**
 * Shared test fixture for Pangea Chat E2E tests.
 *
 * Flutter renders to <canvas>, so Playwright can only interact with the
 * semantics tree. This fixture enables Flutter's accessibility tree on each page load.
 */
export const test = base.extend({
  page: async ({ page }, use) => {
    // Inject mock: true into all sent choreo requests
    // And redirect to local choreo server
    await page.route('**/choreo/*', (route, request) => {
      const headers = {
        ...request.headers(),
        'mock': 'true',
        'mock_llm_latency_override_s': '0',
      };
      route.continue({
        headers: headers
      });
    });

    // Navigate to the app and wait for Flutter to render
    await page.goto("/");

    // Enable Flutter's semantics tree. When the app is built with
    // ENABLE_SEMANTICS=true it is already on (the placeholder is absent), so
    // this is skipped. Otherwise click the off-screen "Enable accessibility"
    // placeholder; dispatchEvent is required because the element sits off-screen
    // and .click() (even force:true) cannot reach it.
    // See playwright-testing.instructions.md.
    const enableButton = page.getByRole("button", {
      name: "Enable accessibility",
    });
    if (await enableButton.count()) {
      await enableButton.dispatchEvent("click", { timeout: 15000 });
    }

    // Wait for semantics tree to populate after enabling
    await page.waitForTimeout(3000);

    await use(page);
  },
});

export { expect };
