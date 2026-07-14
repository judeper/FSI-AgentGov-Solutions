import { expect, test } from '@playwright/test';
import { resolvePortalBaseUrl } from '../src/config-helpers';
import { assertNoInteractiveAuth } from '../src/portal-helpers';

test('portal smoke template fails fast on interactive auth', async ({ page }) => {
  const baseUrl = resolvePortalBaseUrl(process.env);
  test.skip(!baseUrl, 'Set LAB_PORTAL_BASE_URL to run portal smoke checks.');

  await page.goto(baseUrl!, { waitUntil: 'domcontentloaded' });
  await assertNoInteractiveAuth(page);
  await expect(page.locator('body')).toBeVisible();
});
