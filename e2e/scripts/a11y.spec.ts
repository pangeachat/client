import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "../fixtures";

/**
 * Accessibility regression tests via axe-core.
 *
 * Runs WCAG 2.1 AA audits against pages that have Flutter semantics
 * coverage. Scoped to the semantics overlay (<flt-semantics-host>)
 * since Flutter's <canvas> is opaque to axe.
 *
 * Triggers:
 * - lib/pangea/login/**
 * - lib/pages/login/**
 * - lib/pangea/chat_list/**
 * - lib/pages/chat_list/**
 * - e2e/scripts/a11y.spec.ts
 */

/**
 * Runs an axe audit scoped to Flutter's semantics overlay.
 * Returns only violations so tests can assert on them.
 */
async function auditPage(page: import("@playwright/test").Page) {
  const results = await new AxeBuilder({ page })
    .include("flt-semantics-host") // Only audit the semantics overlay, not the canvas
    .withTags(["wcag2a", "wcag2aa", "wcag21aa"]) // WCAG 2.1 AA
    .analyze();

  return results.violations;
}

test.describe("Accessibility (axe-core)", () => {
  test.describe("Unauthenticated pages", () => {
    test.use({ storageState: { cookies: [], origins: [] } });

    test("landing page has no a11y violations", async ({ page }) => {
      // Fixture navigates to '/' and enables semantics
      await expect(page.getByRole("button", { name: "Start" })).toBeVisible();

      const violations = await auditPage(page);
      expect(violations, formatViolations(violations)).toHaveLength(0);
    });

    test("email login page has no a11y violations", async ({ page }) => {
      await page.getByRole("button", { name: "Login to my account" }).click();
      await page.getByRole("button", { name: "Email" }).click();

      // Wait for form fields to render in semantics tree
      await expect(
        page.getByRole("textbox", { name: "Username or email" }),
      ).toBeVisible();

      const violations = await auditPage(page);
      expect(violations, formatViolations(violations)).toHaveLength(0);
    });
  });

  test.describe("Authenticated pages", () => {
    // Debug mode needs extra time to restore IndexedDB session + sync Matrix
    test.setTimeout(120_000);

    test("chat list has no a11y violations", async ({ page }) => {
      // Auth fixture loads saved state → lands on /rooms or /home
      await expect(page.getByRole("button", { name: "Home" })).toBeVisible({
        timeout: 90000,
      });

      const violations = await auditPage(page);
      expect(violations, formatViolations(violations)).toHaveLength(0);
    });
  });
});

/**
 * Formats axe violations into a readable string for assertion messages.
 */
function formatViolations(violations: import("axe-core").Result[]): string {
  if (violations.length === 0) return "No violations";
  return (
    `\n${violations.length} accessibility violation(s):\n` +
    violations
      .map(
        (v) =>
          `  • [${v.impact}] ${v.id}: ${v.description}\n` +
          `    Help: ${v.helpUrl}\n` +
          `    Nodes: ${v.nodes.map((n) => n.html).join(", ")}`,
      )
      .join("\n")
  );
}
