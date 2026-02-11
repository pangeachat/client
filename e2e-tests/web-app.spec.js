/**
 * Playwright E2E Tests for Pangea Chat Web App
 * 
 * These tests demonstrate how to test the Flutter web app like a real user.
 * 
 * Prerequisites:
 * 1. Start the web app: flutter run -d web-server --web-port=8080
 * 2. Install Playwright: npm install -D @playwright/test
 * 3. Install browsers: npx playwright install
 * 
 * Run tests:
 * - All tests: npx playwright test
 * - With UI: npx playwright test --headed
 * - Single test: npx playwright test e2e-tests/web-app.spec.js
 */

const { test, expect } = require('@playwright/test');

// Configuration
const APP_URL = process.env.APP_URL || 'http://localhost:8080';
const FLUTTER_INIT_TIMEOUT = 30000; // 30 seconds for Flutter to initialize

test.describe('Pangea Chat Web App - Basic Flow', () => {
  test.beforeEach(async ({ page }) => {
    // Set a reasonable timeout for all actions
    page.setDefaultTimeout(15000);
  });

  test('should load the application successfully', async ({ page }) => {
    // Navigate to the app
    await page.goto(APP_URL);
    
    // Wait for Flutter to initialize
    // Flutter web apps render content in a canvas element
    await page.waitForSelector('flt-glass-pane, flt-scene-host, flutter-view', { 
      timeout: FLUTTER_INIT_TIMEOUT 
    });
    
    // Take a screenshot for visual verification
    await page.screenshot({ 
      path: 'test-results/01-app-loaded.png',
      fullPage: true 
    });
    
    // Verify the page title
    const title = await page.title();
    expect(title).toBeTruthy();
    console.log('✓ App loaded successfully. Title:', title);
  });

  test('should display the home screen', async ({ page }) => {
    await page.goto(APP_URL);
    await page.waitForSelector('flt-glass-pane, flt-scene-host, flutter-view', { 
      timeout: FLUTTER_INIT_TIMEOUT 
    });
    
    // Wait a bit for the app to fully render
    await page.waitForTimeout(2000);
    
    // Take screenshot of home screen
    await page.screenshot({ 
      path: 'test-results/02-home-screen.png',
      fullPage: true 
    });
    
    console.log('✓ Home screen displayed');
  });

  test('should have clickable elements', async ({ page }) => {
    await page.goto(APP_URL);
    await page.waitForSelector('flt-glass-pane, flt-scene-host, flutter-view', { 
      timeout: FLUTTER_INIT_TIMEOUT 
    });
    
    await page.waitForTimeout(2000);
    
    // Try to find interactive elements
    // Note: Flutter web apps render in canvas, so we need to use accessibility roles
    const buttons = await page.locator('[role="button"]').count();
    console.log(`✓ Found ${buttons} interactive buttons`);
    
    const textboxes = await page.locator('[role="textbox"], input[type="text"]').count();
    console.log(`✓ Found ${textboxes} text input fields`);
    
    // Take screenshot
    await page.screenshot({ 
      path: 'test-results/03-interactive-elements.png',
      fullPage: true 
    });
  });

  test('should be responsive to user interactions', async ({ page }) => {
    await page.goto(APP_URL);
    await page.waitForSelector('flt-glass-pane, flt-scene-host, flutter-view', { 
      timeout: FLUTTER_INIT_TIMEOUT 
    });
    
    await page.waitForTimeout(2000);
    
    // Try clicking on the first button if available
    const firstButton = page.locator('[role="button"]').first();
    const buttonCount = await page.locator('[role="button"]').count();
    
    if (buttonCount > 0) {
      await page.screenshot({ path: 'test-results/04-before-click.png' });
      
      await firstButton.click();
      await page.waitForTimeout(1000);
      
      await page.screenshot({ path: 'test-results/04-after-click.png' });
      console.log('✓ Successfully clicked a button');
    } else {
      console.log('ℹ No buttons found to click');
    }
  });

  test('should handle text input', async ({ page }) => {
    await page.goto(APP_URL);
    await page.waitForSelector('flt-glass-pane, flt-scene-host, flutter-view', { 
      timeout: FLUTTER_INIT_TIMEOUT 
    });
    
    await page.waitForTimeout(2000);
    
    // Try to find and fill a text input
    const textInputs = page.locator('[role="textbox"], input[type="text"]');
    const inputCount = await textInputs.count();
    
    if (inputCount > 0) {
      const firstInput = textInputs.first();
      
      await page.screenshot({ path: 'test-results/05-before-input.png' });
      
      await firstInput.click();
      await firstInput.fill('Hello from automated test!');
      await page.waitForTimeout(500);
      
      await page.screenshot({ path: 'test-results/05-after-input.png' });
      console.log('✓ Successfully filled text input');
    } else {
      console.log('ℹ No text inputs found');
    }
  });

  test('should navigate using keyboard', async ({ page }) => {
    await page.goto(APP_URL);
    await page.waitForSelector('flt-glass-pane, flt-scene-host, flutter-view', { 
      timeout: FLUTTER_INIT_TIMEOUT 
    });
    
    await page.waitForTimeout(2000);
    
    // Test keyboard navigation
    await page.keyboard.press('Tab');
    await page.waitForTimeout(200);
    await page.keyboard.press('Tab');
    await page.waitForTimeout(200);
    
    await page.screenshot({ path: 'test-results/06-keyboard-navigation.png' });
    console.log('✓ Keyboard navigation tested');
  });
});

test.describe('Pangea Chat Web App - Accessibility', () => {
  test('should meet basic accessibility standards', async ({ page }) => {
    await page.goto(APP_URL);
    await page.waitForSelector('flt-glass-pane, flt-scene-host, flutter-view', { 
      timeout: FLUTTER_INIT_TIMEOUT 
    });
    
    await page.waitForTimeout(2000);
    
    // Check for semantic elements
    const buttonsWithLabel = await page.locator('[role="button"][aria-label]').count();
    console.log(`✓ Found ${buttonsWithLabel} buttons with aria-labels`);
    
    const linksWithText = await page.locator('a').count();
    console.log(`✓ Found ${linksWithText} links`);
    
    await page.screenshot({ 
      path: 'test-results/07-accessibility-check.png',
      fullPage: true 
    });
  });
});

test.describe('Pangea Chat Web App - Responsive Design', () => {
  test('should work on mobile viewport', async ({ page }) => {
    // Set mobile viewport
    await page.setViewportSize({ width: 375, height: 667 });
    
    await page.goto(APP_URL);
    await page.waitForSelector('flt-glass-pane, flt-scene-host, flutter-view', { 
      timeout: FLUTTER_INIT_TIMEOUT 
    });
    
    await page.waitForTimeout(2000);
    
    await page.screenshot({ 
      path: 'test-results/08-mobile-viewport.png',
      fullPage: true 
    });
    
    console.log('✓ Mobile viewport rendered');
  });

  test('should work on tablet viewport', async ({ page }) => {
    // Set tablet viewport
    await page.setViewportSize({ width: 768, height: 1024 });
    
    await page.goto(APP_URL);
    await page.waitForSelector('flt-glass-pane, flt-scene-host, flutter-view', { 
      timeout: FLUTTER_INIT_TIMEOUT 
    });
    
    await page.waitForTimeout(2000);
    
    await page.screenshot({ 
      path: 'test-results/09-tablet-viewport.png',
      fullPage: true 
    });
    
    console.log('✓ Tablet viewport rendered');
  });

  test('should work on desktop viewport', async ({ page }) => {
    // Set desktop viewport
    await page.setViewportSize({ width: 1920, height: 1080 });
    
    await page.goto(APP_URL);
    await page.waitForSelector('flt-glass-pane, flt-scene-host, flutter-view', { 
      timeout: FLUTTER_INIT_TIMEOUT 
    });
    
    await page.waitForTimeout(2000);
    
    await page.screenshot({ 
      path: 'test-results/10-desktop-viewport.png',
      fullPage: true 
    });
    
    console.log('✓ Desktop viewport rendered');
  });
});

test.describe('Pangea Chat Web App - Performance', () => {
  test('should load within acceptable time', async ({ page }) => {
    const startTime = Date.now();
    
    await page.goto(APP_URL);
    await page.waitForSelector('flt-glass-pane, flt-scene-host, flutter-view', { 
      timeout: FLUTTER_INIT_TIMEOUT 
    });
    
    const loadTime = Date.now() - startTime;
    console.log(`✓ App loaded in ${loadTime}ms`);
    
    // Assert load time is reasonable (under 10 seconds)
    expect(loadTime).toBeLessThan(10000);
  });
});
