const { defineConfig } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const port = process.env.PLAYWRIGHT_PORT || '3310';
const rvm = path.join(process.env.HOME || '', '.rvm/bin/rvm');
const rubyVersionFile = path.join(__dirname, '.ruby-version');
const rubyVersion = fs.existsSync(rubyVersionFile)
  ? fs.readFileSync(rubyVersionFile, 'utf8').trim()
  : '';
const railsPrefix = fs.existsSync(rvm) && rubyVersion ? `${rvm} ${rubyVersion} do ` : '';

module.exports = defineConfig({
  testDir: './playwright',
  testMatch: '**/*.spec.js',
  timeout: 30000,
  fullyParallel: false,
  workers: 1,
  use: {
    baseURL: process.env.PLAYWRIGHT_BASE_URL || `http://127.0.0.1:${port}`,
    headless: true
  },
  webServer: {
    command: `${railsPrefix}bin/rails server -e test -p ${port} -b 127.0.0.1`,
    env: {
      DATABASE_URL: 'sqlite3:storage/playwright.sqlite3'
    },
    url: `http://127.0.0.1:${port}/users/sign_in`,
    reuseExistingServer: !process.env.CI,
    timeout: 120000
  }
});
