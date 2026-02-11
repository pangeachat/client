# Flutter Web App Testing Guide

This guide demonstrates how to run and test the Pangea Chat Flutter web application like a real user using browser automation.

## Prerequisites

1. **Flutter SDK** (version ≥3.0)
   ```bash
   flutter --version
   ```

2. **Google Chrome** (for running the web app)
   ```bash
   google-chrome --version
   ```

3. **Node.js** (for Playwright browser automation, optional)
   ```bash
   node --version
   ```

## Running the Flutter Web App

### Option 1: Development Mode (Hot Reload)

```bash
# Navigate to project directory
cd /path/to/client

# Run in Chrome with hot reload
flutter run -d chrome --web-port=8080
```

### Option 2: Release Mode (Production Build)

```bash
# Build the web app
flutter build web --release

# Serve the built app using a local server
cd build/web
python3 -m http.server 8080
# Or using Node.js
# npx serve -p 8080
```

### Option 3: Web Server Mode (For Remote/WSL)

```bash
# Run as web server (useful for WSL or remote connections)
flutter run --release -d web-server --web-port=8080
```

The app will be accessible at `http://localhost:8080`

## Manual Testing

Once the app is running, you can test it manually in a browser:

1. **Open the app**: Navigate to `http://localhost:8080`
2. **Login flow**: Test user registration/login
3. **Chat features**: Send messages, create rooms
4. **Language learning**: Test IGC (Interactive Grammar Correction)
5. **Activities**: Try practice activities

## Automated Testing with Playwright

Playwright allows you to automate browser interactions and test the web app like a real user would.

### Setup Playwright

```bash
# Install Playwright (if not already installed)
npm install -D @playwright/test
npx playwright install chromium
```

### Example Test Script

Create `e2e-tests/web-app.spec.js`:

```javascript
const { test, expect } = require('@playwright/test');

test.describe('Pangea Chat Web App', () => {
  test('should load the home page', async ({ page }) => {
    // Navigate to the app
    await page.goto('http://localhost:8080');
    
    // Wait for Flutter to initialize
    await page.waitForSelector('flt-scene-host', { timeout: 30000 });
    
    // Take a screenshot
    await page.screenshot({ path: 'screenshots/home-page.png' });
    
    // Check if the app loaded
    expect(await page.title()).toBeTruthy();
  });

  test('should navigate to login page', async ({ page }) => {
    await page.goto('http://localhost:8080');
    await page.waitForSelector('flt-scene-host', { timeout: 30000 });
    
    // Look for login-related elements
    // Note: Flutter web renders in a canvas, so we need to use accessibility or text content
    const loginButton = page.getByRole('button', { name: /sign in|login/i });
    if (await loginButton.isVisible()) {
      await loginButton.click();
      await page.screenshot({ path: 'screenshots/login-page.png' });
    }
  });

  test('should handle chat input', async ({ page }) => {
    await page.goto('http://localhost:8080');
    await page.waitForSelector('flt-scene-host', { timeout: 30000 });
    
    // Simulate user login and navigation
    // This would require actual credentials for a full test
    
    // Example: Find and interact with text input
    const textInput = page.getByRole('textbox').first();
    if (await textInput.isVisible()) {
      await textInput.fill('Hello, world!');
      await page.screenshot({ path: 'screenshots/chat-input.png' });
    }
  });
});
```

### Running the Tests

```bash
# Run all tests
npx playwright test

# Run tests in headed mode (see the browser)
npx playwright test --headed

# Run a specific test file
npx playwright test e2e-tests/web-app.spec.js

# Generate test report
npx playwright show-report
```

## Integration Tests (Flutter Native)

The project already includes Flutter integration tests in `integration_test/`:

```bash
# Run Flutter integration tests
flutter test integration_test/app_test.dart

# Run with Chrome driver
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/app_test.dart \
  -d chrome
```

## Testing Workflow

1. **Start the web server**:
   ```bash
   flutter run -d web-server --web-port=8080
   ```

2. **Run manual exploratory tests** in the browser

3. **Run automated Playwright tests**:
   ```bash
   npx playwright test --headed
   ```

4. **Review screenshots and reports** in the `test-results/` directory

5. **Run Flutter integration tests** for deeper widget-level testing:
   ```bash
   flutter test integration_test/
   ```

## CI/CD Integration

Add to `.github/workflows/web-testing.yml`:

```yaml
name: Web Testing

on: [push, pull_request]

jobs:
  web-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.16.9'
      
      - name: Install dependencies
        run: flutter pub get
      
      - name: Build web app
        run: flutter build web --release
      
      - name: Setup Node.js
        uses: actions/setup-node@v3
        with:
          node-version: '18'
      
      - name: Install Playwright
        run: |
          npm install -D @playwright/test
          npx playwright install chromium
      
      - name: Serve web app
        run: |
          cd build/web
          python3 -m http.server 8080 &
          sleep 5
      
      - name: Run Playwright tests
        run: npx playwright test
      
      - name: Upload test results
        uses: actions/upload-artifact@v3
        if: always()
        with:
          name: test-results
          path: test-results/
```

## Tips for Testing Flutter Web Apps

1. **Wait for Flutter initialization**: Flutter web apps render in a canvas, so always wait for the `flt-scene-host` element
2. **Use accessibility selectors**: Prefer `getByRole()`, `getByLabel()` over CSS selectors
3. **Handle async operations**: Use `waitForSelector()` and `waitForTimeout()` generously
4. **Take screenshots**: Capture visual evidence of test execution
5. **Test across browsers**: Run tests in Chrome, Firefox, and Safari
6. **Mobile viewports**: Test responsive behavior with different viewport sizes

## Debugging

```bash
# Run in debug mode with DevTools
flutter run -d chrome --web-port=8080 --web-browser-debug-port=9222

# Run Playwright in debug mode
PWDEBUG=1 npx playwright test

# Generate trace for debugging
npx playwright test --trace on
```

## Troubleshooting

- **App not loading**: Check if Flutter web server is running on the expected port
- **Selector not found**: Flutter web uses canvas rendering; use semantic selectors
- **Timeout errors**: Increase timeout values for slower machines
- **CORS issues**: Ensure proper CORS configuration in `.env` file

## Resources

- [Flutter Web Documentation](https://docs.flutter.dev/platform-integration/web)
- [Playwright Documentation](https://playwright.dev/)
- [Flutter Integration Testing](https://docs.flutter.dev/testing/integration-tests)
