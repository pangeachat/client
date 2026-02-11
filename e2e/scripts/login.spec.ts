import { test, expect } from '../fixtures';

/**
 * Login flow test
 * 
 * Triggers:
 * - lib/pangea/login/**
 * - lib/pages/login/**
 * - lib/config/routes.dart
 * - lib/widgets/matrix.dart
 */

test.describe('Login', () => {
  test.use({ storageState: { cookies: [], origins: [] } }); // Don't use saved auth for login test
  
  test('should display landing page and login successfully', async ({ page }) => {
    // Navigate to the app
    await page.goto('/');
    
    // Enable Flutter semantics tree
    await page.evaluate(() => {
      const el = document.querySelector('flt-semantics-placeholder');
      if (el) {
        (el as HTMLElement).click();
      }
    });
    await page.waitForTimeout(2000);
    
    // Verify landing page elements are visible
    await expect(page.getByRole('button', { name: 'Start' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Login to my account' })).toBeVisible();
    
    // Click "Login to my account"
    await page.getByRole('button', { name: 'Login to my account' }).click();
    
    // Click "Email" login method
    await page.getByRole('button', { name: 'Email' }).click();
    
    // Fill credentials
    await page.getByRole('textbox', { name: 'Username or email' }).fill(process.env.TEST_USER!);
    await page.getByRole('textbox', { name: 'Password' }).fill(process.env.TEST_PASSWORD!);
    
    // Click login
    await page.getByRole('button', { name: 'Login' }).click();
    
    // Wait for chat list to load
    await expect(page).toHaveURL(/\/rooms/, { timeout: 10000 });
    
    // Verify chat list is visible
    // The Search button tooltip was added in Phase 1
    await expect(page.getByRole('button', { name: 'Search' })).toBeVisible();
  });
});
