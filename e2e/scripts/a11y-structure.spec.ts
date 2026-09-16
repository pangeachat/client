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
 *   - 3.2.1 On Focus ............. a closing menu hands DOM focus straight back
 *                                  to the control that opened it (gate)
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
  path: string,
  sentinel: import("@playwright/test").Locator,
) {
  await page.goto(path);
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

  const surfaces: { name: string; path: string; sentinel: (p: any) => any }[] = [
    { name: "world map", path: "/", sentinel: (p) => p.getByRole("textbox", { name: intl.mapSearchHint }) },
    { name: "chat list", path: "/?left=chats", sentinel: (p) => p.getByRole("button", { name: intl.chatWithSupport }).first() },
    { name: "settings", path: "/?right=settings", sentinel: (p) => p.getByRole("button", { name: intl.learningSettings }).first() },
  ];

  for (const s of surfaces) {
    test(`${s.name}: title + keyboard operability`, async ({ page }) => {
      await gotoSurface(page, s.path, s.sentinel(page));

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

  // 3.2.1 On Focus — a menu that closes must hand DOM focus straight back to the
  // control that opened it, in one move (#9049). Two ways it goes wrong, both
  // visible to a screen reader as a flash to the page root: the focused item's
  // element is removed first, and the engine parks focus on <flutter-view>; or
  // the pill already holds focus but its page subtree is re-inserted as the
  // menu goes, which knocks focus off and back on. Flutter's own focus tree
  // recovers either way, so this is asserted at the DOM, where the reader is.
  test("world map: a closing filter menu returns focus to its pill in one step", async ({ page }) => {
    await gotoSurface(page, "/", surfaces[0].sentinel(page));

    const pill = page.getByRole("button", { name: intl.mapFilterAllLevels }).first();
    await expect(pill).toBeVisible({ timeout: 30_000 });

    // Record every element that takes focus, not just where it settles: it
    // settles on the pill either way, and the detour is the fault.
    const pillId = await pill.evaluate((el: HTMLElement) => {
      el.focus();
      (window as any).__focusins = [];
      document.addEventListener(
        "focusin",
        (e) => (window as any).__focusins.push((e.target as HTMLElement).tagName.toLowerCase()),
        true,
      );
      return el.id;
    });
    expect(await page.evaluate(() => document.activeElement?.id), "pill never took focus").toBe(pillId);

    const drain = () =>
      page.evaluate(() => {
        const seen = (window as any).__focusins as string[];
        (window as any).__focusins = [];
        return seen;
      });

    // Enter opens the menu; it is then closed both ways — Escape, and Enter on
    // the auto-focused first item, which picks "All levels", the value the pill
    // already holds, so the second pass starts where the first did.
    for (const closeKey of ["Escape", "Enter"]) {
      await page.keyboard.press("Enter");
      await page.waitForTimeout(700);
      await drain();

      await page.keyboard.press(closeKey);
      await page.waitForTimeout(1000);

      const seen = await drain();
      expect(seen, `closing with ${closeKey} did not move focus to the pill in one step; focusins=${JSON.stringify(seen)}`).toEqual(["flt-semantics"]);
      expect(await page.evaluate(() => document.activeElement?.id), `closing with ${closeKey} did not leave focus on the pill`).toBe(pillId);
    }
  });
});
