# E2E Tests for Pangea Chat Web App

This directory contains end-to-end (E2E) tests for the Pangea Chat Flutter web application using Playwright.

## Quick Start

### 1. Install Dependencies

```bash
cd e2e-tests
npm install
npm run install:browsers
```

### 2. Start the Web App

In a separate terminal:

```bash
cd ..
flutter run -d web-server --web-port=8080
```

Or serve a built version:

```bash
flutter build web --release
cd build/web
python3 -m http.server 8080
```

### 3. Run Tests

```bash
npm test                 # Run all tests
npm run test:headed      # Run with browser UI visible
npm run test:debug       # Run in debug mode
npm run test:ui          # Run with Playwright UI mode
npm run test:report      # View test report
```

## Test Structure

- `web-app.spec.js` - Main test suite covering:
  - Basic application loading
  - User interactions (clicks, text input)
  - Keyboard navigation
  - Accessibility checks
  - Responsive design (mobile, tablet, desktop)
  - Performance metrics

## Configuration

Test configuration is in `../playwright.config.js`. Key settings:

- **Base URL**: `http://localhost:8080` (configurable via `APP_URL` env var)
- **Timeout**: 60 seconds per test
- **Browsers**: Chromium, Firefox, WebKit
- **Screenshots**: Captured on failure
- **Videos**: Recorded on failure

## Environment Variables

```bash
# Set custom app URL
export APP_URL=http://localhost:3000

# Run in CI mode
export CI=true

# Run tests
npm test
```

## Writing New Tests

### Example Test

```javascript
const { test, expect } = require('@playwright/test');

test('should do something', async ({ page }) => {
  await page.goto('http://localhost:8080');
  
  // Wait for Flutter to initialize
  await page.waitForSelector('flt-glass-pane, flt-scene-host', { 
    timeout: 30000 
  });
  
  // Your test actions here
  const button = page.getByRole('button', { name: 'Click me' });
  await button.click();
  
  // Assertions
  expect(await page.title()).toBe('Expected Title');
});
```

### Tips for Flutter Web Testing

1. **Wait for Flutter initialization**: Always wait for `flt-glass-pane` or `flt-scene-host` selectors
2. **Use semantic selectors**: Prefer `getByRole()`, `getByLabel()` over CSS selectors
3. **Add delays**: Flutter animations may need small delays (`waitForTimeout`)
4. **Take screenshots**: Capture visual evidence with `page.screenshot()`
5. **Use accessibility**: Flutter web apps should have proper ARIA labels

## Test Results

After running tests, results are available in:

- `test-results/` - Screenshots, videos, traces
- `playwright-report/` - HTML report (view with `npm run test:report`)

## Debugging

### Debug a specific test

```bash
npx playwright test e2e-tests/web-app.spec.js --debug
```

### Generate test code

```bash
npm run test:codegen
```

This opens a browser where you can interact with the app, and Playwright generates test code automatically.

### View traces

```bash
npx playwright show-trace test-results/trace.zip
```

## CI Integration

For GitHub Actions, add this workflow:

```yaml
- name: Run E2E tests
  run: |
    cd e2e-tests
    npm install
    npx playwright install chromium
    npm test
```

## Troubleshooting

### App not loading

- Ensure Flutter web server is running: `flutter run -d web-server --web-port=8080`
- Check the port is correct (default: 8080)
- Try accessing http://localhost:8080 in a browser manually

### Timeout errors

- Increase timeout in test: `page.setDefaultTimeout(30000)`
- Flutter apps can take 10-30 seconds to initialize on first load

### Selectors not found

- Flutter web uses canvas rendering, so CSS selectors may not work
- Use ARIA roles: `page.getByRole('button')`
- Use text content: `page.getByText('Login')`
- Add explicit waits: `await page.waitForTimeout(2000)`

### Browser installation issues

```bash
# Install specific browser
npx playwright install chromium

# Install all browsers
npx playwright install
```

## Resources

- [Playwright Documentation](https://playwright.dev/)
- [Flutter Web Documentation](https://docs.flutter.dev/platform-integration/web)
- [Testing Flutter Web Apps](https://docs.flutter.dev/testing)
