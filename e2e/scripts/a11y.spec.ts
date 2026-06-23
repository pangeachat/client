import AxeBuilder from "@axe-core/playwright";
import fs from "fs";
import path from "path";
import { expect, test } from "../fixtures";

/**
 * Accessibility regression tests via axe-core.
 *
 * Runs WCAG 2.1 AA audits against pages that have Flutter semantics
 * coverage. Scoped to the semantics overlay (<flt-semantics-host>)
 * since Flutter's <canvas> is opaque to axe.
 *
 * Triggers (world_v2): see e2e/trigger-map.json for the authoritative globs.
 * - lib/routes/world/**, lib/features/navigation/**, lib/widgets/layouts/**
 * - lib/routes/chat_list/**, lib/routes/home/login/**
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

/**
 * Reach an authenticated world_v2 surface and prove it rendered before auditing.
 * The home is a canvas map; flutter_map defers its semantics tree until a pointer
 * event, so we wake it, then wait for a surface-specific control. Auditing before
 * the surface is in the tree would report zero violations vacuously.
 */
async function gotoSurface(
  page: import("@playwright/test").Page,
  hash: string,
  sentinel: import("@playwright/test").Locator,
) {
  await page.goto(hash);
  await page.mouse.move(640, 400);
  await page.mouse.wheel(0, -500);
  await expect(sentinel).toBeVisible({ timeout: 90_000 });
}

test.describe("Accessibility (axe-core)", () => {
  // Do not use saved login state
  test.use({ storageState: { cookies: [], origins: [] } }); 

  // Use intl key values as object names
  const filePath = path.resolve(__dirname, '../../lib/l10n/intl_en.arb');
  const fileContent = fs.readFileSync(filePath, 'utf-8');
  const intl = JSON.parse(fileContent);

  test.describe("Unauthenticated pages", () => {
    test("landing page has no a11y violations", async ({ page }) => {
      // Fixture navigates to '/' and enables semantics
      await expect(page.getByRole("button", { name: intl.getStarted })).toBeVisible();

      const violations = await auditPage(page);
      expect(violations, formatViolations(violations)).toHaveLength(0);
    });

    test("email login page has no a11y violations", async ({ page }) => {
      await page.getByRole("button", { name: intl.loginToAccount }).click();
      await page.getByRole("button", { name: intl.email }).click();

      // Wait for form fields to render in semantics tree
      await expect(
        page.getByRole("textbox", { name: intl.usernameOrEmail }),
      ).toBeVisible();

      const violations = await auditPage(page);
      expect(violations, formatViolations(violations)).toHaveLength(0);
    });
  });

  test.describe("Authenticated world_v2 surfaces", () => {
    // Re-attach the saved auth state; the parent describe forces logged-out.
    test.use({
      storageState: path.join(__dirname, "..", ".auth", "user.json"),
    });
    // Login + IndexedDB session restore + Matrix sync need extra time.
    test.setTimeout(120_000);

    test("world map has no a11y violations", async ({ page }) => {
      await gotoSurface(
        page,
        "/#/",
        page.getByRole("textbox", { name: intl.mapSearchHint }),
      );
      const violations = await auditPage(page);
      expect(violations, formatViolations(violations)).toHaveLength(0);
    });

    test("chat list has no a11y violations", async ({ page }) => {
      await gotoSurface(
        page,
        "/#/?left=chats",
        page.getByRole("button", { name: intl.chatWithSupport }).first(),
      );
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
