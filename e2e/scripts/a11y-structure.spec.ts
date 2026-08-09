import fs from "fs";
import path from "path";
import { expect, test } from "../fixtures";

/**
 * Deterministic structural a11y gates — the checks that need no pixel judgment
 * and so can fail the build like axe does. Complements a11y.spec.ts (which
 * audits name/role/value) by proving the canvas app is keyboard-operable.
 *
 *   - 2.4.2 Page Titled .......... document.title is non-empty (gate)
 *   - 2.1.1 Keyboard ............. Tab reaches multiple distinct controls (gate)
 *   - 2.1.2 No Keyboard Trap ..... focus is not pinned to one node (gate)
 *
 * Reported, not gated (see accessibility.instructions.md tiering):
 *   - 2.4.2 distinct-per-view titles (known gap; logged)
 *   - 2.5.8 Target Size — WCAG 2.2, outside the attested 2.1 AA standard (logged)
 *
 * Run locally against a profile build (debug stalls on splash):
 *   BASE_URL=http://localhost:8091 npx playwright test --config=e2e/playwright.config.ts \
 *     e2e/scripts/a11y-structure.spec.ts --project=chromium --no-deps
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

/** Tab through the surface, returning the focused control's descriptor per step. */
async function tabRing(page: import("@playwright/test").Page, steps: number) {
  const ring: string[] = [];
  for (let i = 0; i < steps; i++) {
    await page.keyboard.press("Tab");
    await page.waitForTimeout(120);
    ring.push(
      await page.evaluate(() => {
        const a = document.activeElement as HTMLElement | null;
        if (!a || a === document.body) return "<none>";
        const label =
          a.getAttribute("aria-label") ||
          a.textContent?.trim().slice(0, 30) ||
          "";
        const role = a.getAttribute("role");
        return `${a.tagName.toLowerCase()}${role ? "[" + role + "]" : ""} "${label}"`;
      }),
    );
  }
  return ring;
}

function maxConsecutive(ring: string[]): number {
  let max = 1;
  let run = 1;
  for (let i = 1; i < ring.length; i++) {
    run = ring[i] === ring[i - 1] ? run + 1 : 1;
    if (run > max) max = run;
  }
  return max;
}

/** Labeled interactive nodes under 24x24 CSS px (2.5.8; reported only). */
async function smallTargets(page: import("@playwright/test").Page) {
  return page.evaluate(() => {
    const host = document.querySelector("flt-semantics-host");
    if (!host) return [] as { label: string; role: string; w: number; h: number }[];
    const out: { label: string; role: string; w: number; h: number }[] = [];
    for (const el of Array.from(
      host.querySelectorAll(
        '[role="button"],[role="link"],[role="checkbox"],[role="switch"],[role="tab"],[role="textbox"]',
      ),
    )) {
      if (el.querySelector("[aria-label]")) continue;
      const r = el.getBoundingClientRect();
      if (r.width === 0 || r.height === 0) continue;
      if (r.width < 24 || r.height < 24)
        out.push({
          label: (el.getAttribute("aria-label") || "").slice(0, 30),
          role: el.getAttribute("role") || "",
          w: Math.round(r.width),
          h: Math.round(r.height),
        });
    }
    return out;
  });
}

test.describe("Structural a11y gates", () => {
  test.use({ storageState: path.join(__dirname, "..", ".auth", "user.json") });
  test.setTimeout(120_000);

  const intl = JSON.parse(
    fs.readFileSync(path.resolve(__dirname, "../../lib/l10n/intl_en.arb"), "utf-8"),
  );

  const surfaces: { name: string; hash: string; sentinel: (p: any) => any }[] = [
    { name: "world map", hash: "/#/", sentinel: (p) => p.getByRole("textbox", { name: intl.mapSearchHint }) },
    { name: "chat list", hash: "/#/?left=chats", sentinel: (p) => p.getByRole("button", { name: intl.chatWithSupport }).first() },
    { name: "settings", hash: "/#/?right=settings", sentinel: (p) => p.getByRole("button", { name: intl.learningSettings }).first() },
  ];

  for (const s of surfaces) {
    test(`${s.name}: title + keyboard operability`, async ({ page }) => {
      await gotoSurface(page, s.hash, s.sentinel(page));

      // 2.4.2 Page Titled — a non-empty document title must be present.
      expect((await page.title()).trim().length, "document.title is empty").toBeGreaterThan(0);

      // 2.1.1 Keyboard — Tab must reach several distinct controls (focus enters
      // the canvas app and progresses, not stuck on <body>/<none>).
      const ring = await tabRing(page, 15);
      const real = ring.filter((r) => r !== "<none>");
      const distinct = new Set(real).size;
      expect(distinct, `too few keyboard-reachable controls; ring=${JSON.stringify(ring)}`).toBeGreaterThanOrEqual(4);

      // 2.1.2 No Keyboard Trap — focus must not pin to one node for many steps.
      expect(maxConsecutive(real), `focus appears trapped; ring=${JSON.stringify(ring)}`).toBeLessThanOrEqual(5);

      // Reports (non-gating): target-size + the per-view title value.
      const small = await smallTargets(page);
      // eslint-disable-next-line no-console
      console.log(
        `[report] ${s.name}: title="${await page.title()}" | keyboard distinct=${distinct} | <24px targets=${small.length}` +
          (small.length ? " -> " + small.slice(0, 6).map((t) => `${t.w}x${t.h}[${t.role}]"${t.label}"`).join(", ") : ""),
      );
    });
  }
});
