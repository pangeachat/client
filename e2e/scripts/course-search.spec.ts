import fs from "fs";
import path from "path";
import { expect, test } from "../fixtures";

/**
 * Course search focus regression test (#8581).
 *
 * Triggers:
 * - lib/routes/courses/**
 * - lib/features/course_plans/**
 *
 * Clicking the search toggle in Browse Public Courses swaps the toggle for
 * the search field and auto-focuses it. On web with the semantics tree on, a
 * mistimed focus grant loses a race against the removed toggle's async blur
 * (Blink only) and leaves a field that looks focused but swallows every
 * keystroke. So this spec types WITHOUT clicking or focusing the field —
 * real keystrokes landing in the field is the behavior under test.
 */

test.describe("Course search", () => {
  test("typing works immediately after opening search", async ({ page }) => {
    // Use intl key values as object names
    const filePath = path.resolve(__dirname, "../../lib/l10n/intl_en.arb");
    const intl = JSON.parse(fs.readFileSync(filePath, "utf-8"));

    // The panel loads over the map; give the first paint a boot-scale window.
    test.setTimeout(120000);

    await page.goto("/?left=addcoursepage:browse");

    const searchToggle = page.getByRole("button", {
      name: intl.search,
      exact: true,
    });
    await expect(searchToggle).toBeVisible({ timeout: 60000 });
    await searchToggle.click();

    const field = page.getByRole("textbox", {
      name: intl.searchPublicCourses,
    });
    await expect(field).toBeVisible();

    // Human-scale pause between the click and typing, then keystrokes only —
    // no click on the field. The auto-focus must have made the field the real
    // keyboard target on its own.
    await page.waitForTimeout(500);
    await page.keyboard.type("cafe", { delay: 80 });
    await expect(field).toHaveValue("cafe");
  });
});
