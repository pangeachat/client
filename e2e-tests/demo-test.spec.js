/**
 * Demo test for the Flutter web demo page
 * This demonstrates how Playwright can test web apps like a real user
 */

const { test, expect } = require('@playwright/test');

test.describe('Flutter Web Demo - User Interaction Test', () => {
  const DEMO_URL = 'file://' + __dirname + '/../demo/flutter-web-demo.html';

  test('should load the demo page successfully', async ({ page }) => {
    await page.goto(DEMO_URL);
    
    // Verify page loaded
    await expect(page).toHaveTitle('Pangea Chat - Demo');
    
    // Verify main heading
    const heading = page.locator('h1');
    await expect(heading).toHaveText('Pangea Chat');
    
    console.log('✓ Page loaded successfully');
  });

  test('should display all form elements', async ({ page }) => {
    await page.goto(DEMO_URL);
    
    // Check for form elements
    const usernameInput = page.locator('#username');
    const emailInput = page.locator('#email');
    const passwordInput = page.locator('#password');
    const submitButton = page.locator('button[type="submit"]');
    
    await expect(usernameInput).toBeVisible();
    await expect(emailInput).toBeVisible();
    await expect(passwordInput).toBeVisible();
    await expect(submitButton).toBeVisible();
    
    console.log('✓ All form elements are visible');
  });

  test('should accept text input like a real user', async ({ page }) => {
    await page.goto(DEMO_URL);
    
    // Fill form like a real user would
    await page.locator('#username').click();
    await page.locator('#username').fill('testuser');
    
    await page.locator('#email').click();
    await page.locator('#email').fill('test@pangea.chat');
    
    await page.locator('#password').click();
    await page.locator('#password').fill('SecurePassword123');
    
    // Verify values were entered
    await expect(page.locator('#username')).toHaveValue('testuser');
    await expect(page.locator('#email')).toHaveValue('test@pangea.chat');
    await expect(page.locator('#password')).toHaveValue('SecurePassword123');
    
    console.log('✓ Form inputs work correctly');
  });

  test('should submit form and show success message', async ({ page }) => {
    await page.goto(DEMO_URL);
    
    // Fill the form
    await page.locator('#username').fill('testuser');
    await page.locator('#email').fill('test@pangea.chat');
    await page.locator('#password').fill('SecurePassword123');
    
    // Take screenshot before submit
    await page.screenshot({ path: 'test-results/demo-before-submit.png' });
    
    // Submit the form
    await page.locator('button[type="submit"]').click();
    
    // Wait for success message
    await page.waitForTimeout(500);
    
    // Verify success message appears
    const message = page.locator('#message');
    await expect(message).toBeVisible();
    await expect(message).toContainText('Login successful');
    
    // Take screenshot after submit
    await page.screenshot({ path: 'test-results/demo-after-submit.png' });
    
    console.log('✓ Form submission works correctly');
  });

  test('should display feature list', async ({ page }) => {
    await page.goto(DEMO_URL);
    
    // Check that all features are displayed
    const features = page.locator('.feature-item');
    const count = await features.count();
    
    expect(count).toBe(4);
    
    // Verify specific features
    await expect(page.locator('.feature-item').nth(0)).toContainText('Interactive Grammar Correction');
    await expect(page.locator('.feature-item').nth(1)).toContainText('Real-time language assistance');
    await expect(page.locator('.feature-item').nth(2)).toContainText('Chat with native speakers');
    await expect(page.locator('.feature-item').nth(3)).toContainText('Practice activities');
    
    console.log('✓ All features displayed correctly');
  });

  test('should have proper accessibility attributes', async ({ page }) => {
    await page.goto(DEMO_URL);
    
    // Check ARIA labels
    const usernameInput = page.locator('[aria-label="Username"]');
    const emailInput = page.locator('[aria-label="Email"]');
    const passwordInput = page.locator('[aria-label="Password"]');
    const submitButton = page.locator('[aria-label="Sign In"]');
    
    await expect(usernameInput).toBeVisible();
    await expect(emailInput).toBeVisible();
    await expect(passwordInput).toBeVisible();
    await expect(submitButton).toBeVisible();
    
    console.log('✓ Accessibility attributes present');
  });

  test('should work on mobile viewport', async ({ page }) => {
    // Set mobile viewport
    await page.setViewportSize({ width: 375, height: 667 });
    
    await page.goto(DEMO_URL);
    
    // Verify elements are still visible and functional
    await expect(page.locator('h1')).toBeVisible();
    await expect(page.locator('#username')).toBeVisible();
    
    // Fill form on mobile
    await page.locator('#username').fill('mobileuser');
    await expect(page.locator('#username')).toHaveValue('mobileuser');
    
    await page.screenshot({ path: 'test-results/demo-mobile-view.png' });
    
    console.log('✓ Mobile viewport works correctly');
  });
});
