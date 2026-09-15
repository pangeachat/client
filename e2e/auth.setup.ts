import type { Page } from "@playwright/test";
import fs from "fs";
import path from "path";
import { expect, test } from "./fixtures";

/**
 * Authentication setup - logs in once and saves auth state for all tests.
 *
 * Uses environment variables from .env (local) or AWS Secrets Manager (CI):
 * - TEST_MATRIX_USERNAME: Matrix username (localpart, no @ or domain)
 * - TEST_MATRIX_PASSWORD: Password
 */

const authFile = path.join(__dirname, ".auth", "user.json");

test("authenticate", async ({ page }) => {  
  // Use intl key values as object names
  const filePath = path.resolve(__dirname, '../lib/l10n/intl_en.arb');
  const fileContent = fs.readFileSync(filePath, 'utf-8');
  const intl = JSON.parse(fileContent);

  // Avoid test timing out on login 
  test.setTimeout(120000); 

  // If button can't be found, requirements of test may not be met.
  // A debug-mode cold boot can take well over a minute (thousands of DDC
  // module loads on a cache-less Playwright context), so give the landing
  // page a boot-scale window rather than the 5s expect default.
  await expect(page.getByRole("button", { name: intl.loginToAccount }), { message: 'Ensure the system language is english, and the account is not already authenticated.' }).toBeEnabled({ timeout: 120000 });

  await page.getByRole("button", { name: intl.loginToAccount }).click();

  // Click "Email" login method
  await page.getByRole("button", { name: intl.email }).click();

  // Fill username/email — click to focus first, Flutter needs explicit focus
  const usernameField = page.getByRole("textbox", {
    name: intl.usernameOrEmail,
  });
  await usernameField.click();
  await usernameField.fill(process.env.TEST_MATRIX_USERNAME!);

  // Fill password
  const passwordField = page.getByRole("textbox", { name: intl.password });
  await passwordField.click();
  await page.waitForTimeout(500);
  await passwordField.fill(process.env.TEST_MATRIX_PASSWORD!);

  // Click login button once it's enabled
  const loginButton = page.getByRole("button", { name: intl.login });
  await expect(loginButton).toBeEnabled();
  await loginButton.click();

  // Login involves a Matrix server round-trip, so give it ample time. On
  // world_v2 a successful login lands on the world map (PRoutes.world = '/'),
  // not the retired v1 '#/rooms'. Wait until the app leaves the login flow,
  // which means the Matrix session is established.
  await expect(page).not.toHaveURL(/\/login/, { timeout: 120000 });
  // Let the post-login navigation and the IndexedDB session write settle before
  // capturing storage state.
  await page.waitForTimeout(3000);

  // Save authentication state (indexedDB: true captures Flutter/Matrix
  // session tokens stored in IndexedDB, not just cookies + localStorage)
  await page.context().storageState({ path: authFile, indexedDB: true });
  await repairDroppedFalsyValues(page, authFile);
});

/**
 * Playwright's storageState({ indexedDB: true }) capture drops falsy primitive
 * record values: it branches on the serialized value's own truthiness
 * (storageScript.ts, `_collectDB`), so `false`, `null`, `0`, and `''` are saved
 * as a record with no value field at all, and every spec's restored context
 * re-adds them as `undefined`. The matrix SDK keeps boolean `false` rows in
 * `box_user_device_keys_outdated`, which restored as null and crashed the
 * SDK's `Box.getAllValues` (`null as bool`) on every CI page load — Sentry
 * CLIENT-EEZ / CLIENT-BF0. Until Playwright fixes the capture, re-read each
 * dropped value from the still-open page and put it back in the snapshot:
 * plain falsy primitives survive the restorer's `record.value ?? ...` as-is, a
 * stored `null` needs the restorer's typed `valueEncoded` form, and a record
 * whose key no longer exists is removed rather than restored as `undefined`.
 */
async function repairDroppedFalsyValues(page: Page, file: string) {
  const state = JSON.parse(fs.readFileSync(file, "utf-8"));
  const pageOrigin = new URL(page.url()).origin;
  const dropped: {
    db: string;
    store: string;
    records: unknown[];
    record: { key?: unknown; value?: unknown; valueEncoded?: unknown };
  }[] = [];
  for (const origin of state.origins ?? []) {
    if (origin.origin !== pageOrigin) continue;
    for (const db of origin.indexedDB ?? []) {
      for (const store of db.stores ?? []) {
        for (const record of store.records ?? []) {
          if ("value" in record || "valueEncoded" in record) continue;
          // Falsy keys are dropped by the same Playwright bug, but our stores
          // only use non-empty string keys — leave anything else alone rather
          // than guess at it.
          if (typeof record.key !== "string") continue;
          dropped.push({
            db: db.name,
            store: store.name,
            records: store.records,
            record,
          });
        }
      }
    }
  }
  if (dropped.length === 0) return;

  const values = await page.evaluate(async (queries) => {
    const read = (q: { db: string; store: string; key: string }) =>
      new Promise<unknown>((resolve, reject) => {
        const open = indexedDB.open(q.db);
        open.onerror = () => reject(open.error);
        open.onsuccess = () => {
          const get = open.result
            .transaction(q.store, "readonly")
            .objectStore(q.store)
            .get(q.key);
          get.onerror = () => {
            open.result.close();
            reject(get.error);
          };
          get.onsuccess = () => {
            open.result.close();
            resolve(get.result);
          };
        };
      });
    const out: { missing?: boolean; isNull?: boolean; value?: unknown }[] = [];
    for (const q of queries) {
      const value = await read(q);
      if (value === undefined) out.push({ missing: true });
      else if (value === null) out.push({ isNull: true });
      else out.push({ value });
    }
    return out;
  }, dropped.map(({ db, store, record }) => ({ db, store, key: record.key as string })));

  const repaired: string[] = [];
  dropped.forEach(({ db, store, records, record }, i) => {
    const result = values[i];
    if (result.missing) records.splice(records.indexOf(record), 1);
    else if (result.isNull) record.valueEncoded = { v: "null" };
    else record.value = result.value;
    repaired.push(`${db}/${store}/${record.key}`);
  });
  fs.writeFileSync(file, JSON.stringify(state, null, 2));
  console.log(
    `[auth.setup] restored ${repaired.length} falsy IndexedDB value(s) dropped by storageState: ${repaired.join(", ")}`,
  );
}
