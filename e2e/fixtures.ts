import { test as base, expect } from '@playwright/test';

/**
 * Shared test fixture for Pangea Chat E2E tests.
 * 
 * Flutter renders to <canvas>, so Playwright can only interact with the
 * semantics tree. This fixture enables Flutter's accessibility tree on each page load.
 */
export const test = base.extend({
  page: async ({ page }, use) => {
    // Navigate to the app
    await page.goto('/');
    
    // Enable Flutter semantics tree by clicking the accessibility placeholder
    await page.evaluate(() => {
      const el = document.querySelector('flt-semantics-placeholder');
      if (el) {
        (el as HTMLElement).click();
      }
    });
    
    // Wait for semantics tree to populate
    await page.waitForTimeout(2000);
    
    await use(page);
  },
});

export { expect };
