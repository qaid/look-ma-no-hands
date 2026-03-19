const { defineConfig, devices } = require('@playwright/test');

module.exports = defineConfig({
  testDir: '.',
  testMatch: '*.spec.js',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? 'github' : 'list',

  webServer: {
    command: 'npx serve .. -l 3123 --no-clipboard',
    port: 3123,
    reuseExistingServer: !process.env.CI,
  },

  use: {
    baseURL: 'http://localhost:3123',
  },

  projects: [
    { name: 'mobile-320', use: { viewport: { width: 320, height: 568 } } },
    { name: 'mobile-375', use: { viewport: { width: 375, height: 667 } } },
    { name: 'mobile-414', use: { viewport: { width: 414, height: 896 } } },
    { name: 'tablet-768', use: { viewport: { width: 768, height: 1024 } } },
    { name: 'tablet-1024', use: { viewport: { width: 1024, height: 768 } } },
    { name: 'desktop', use: { ...devices['Desktop Chrome'] } },
  ],
});
