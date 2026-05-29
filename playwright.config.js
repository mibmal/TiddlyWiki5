const { defineConfig, devices } = require('@playwright/test');

/**
 * @see https://playwright.dev/docs/test-configuration
 */
module.exports = defineConfig({
  testDir: './editions/test/',

  // Allow parallel tests
  fullyParallel: true,

  // Prevent accidentally committed "test.only" from wrecking havoc
  forbidOnly: !!process.env.CI,

  // Retry on CI to absorb flaky browser-timing failures (e.g. the in-browser
  // jasmine results bar occasionally not rendering within the timeout under
  // Firefox); run without retries locally.
  retries: process.env.CI ? 2 : 0,

  // How many parallel workers
  workers: process.env.CI ? 1 : undefined,

  // Reporter to use. See https://playwright.dev/docs/test-reporters
  reporter: 'html',

  // Settings shared with all the tests
  use: {
    // Take a screenshot when the test fails
    screenshot: {
      mode: 'only-on-failure',
      fullPage: true
    }
  },

  /* Configure projects for major browsers */
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },

    {
      name: 'firefox',
      use: { ...devices['Desktop Firefox'] },
    },

    {
      name: 'edge',
      use: { ...devices['Desktop Chrome'], channel: 'msedge' },
    }
  ],
});

