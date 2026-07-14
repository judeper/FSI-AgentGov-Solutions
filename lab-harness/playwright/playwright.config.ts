import { defineConfig } from '@playwright/test';
import { resolveStorageStatePath } from './src/config-helpers';

export default defineConfig({
  testDir: './tests',
  timeout: 45_000,
  fullyParallel: false,
  retries: 0,
  reporter: [
    ['list'],
    ['html', { open: 'never', outputFolder: 'playwright-report' }]
  ],
  outputDir: 'test-results',
  use: {
    baseURL: process.env.LAB_PORTAL_BASE_URL?.trim(),
    storageState: resolveStorageStatePath(process.env),
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure'
  }
});
