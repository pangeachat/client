import { test, expect } from './fixtures';

/**
 * Authentication setup - logs in once and saves auth state for all tests.
 * 
 * Uses environment variables:
 * - TEST_USER: Matrix username or email
 * - TEST_PASSWORD: Password
 * 
 * In CI, these are populated from GitHub secrets:
 * - STAGING_TEST_USER
 * - STAGING_TEST_PASSWORD
 */

const authFile = '.auth/user.json';

test('authenticate', async ({ page }) => {
  // Click "Login to my account" button
  await page.getByRole('button', { name: 'Login to my account' }).click();
  
  // Click "Email" login method
  await page.getByRole('button', { name: 'Email' }).click();
  
  // Fill username/email
  await page.getByRole('textbox', { name: 'Username or email' }).fill(process.env.TEST_USER!);
  
  // Fill password
  await page.getByRole('textbox', { name: 'Password' }).fill(process.env.TEST_PASSWORD!);
  
  // Click login button
  await page.getByRole('button', { name: 'Login' }).click();
  
  // Wait for chat list to load (URL should contain /rooms)
  await expect(page).toHaveURL(/\/rooms/);
  
  // Save authentication state
  await page.context().storageState({ path: authFile });
});
