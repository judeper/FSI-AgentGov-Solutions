import type { Page } from '@playwright/test';

const interactiveSignals = [
  'pick an account',
  'use another account',
  'sign in to your account',
  'enter password'
];

export function detectInteractiveAuthSignal(content: string): string | undefined {
  const normalized = content.toLowerCase();
  return interactiveSignals.find((signal) => normalized.includes(signal));
}

export async function assertNoInteractiveAuth(page: Page): Promise<void> {
  const title = await page.title();
  const bodyText = await page.locator('body').innerText();
  const signal = detectInteractiveAuthSignal(`${title}\n${bodyText}`);
  if (signal) {
    throw new Error(
      `Interactive authentication prompt detected (${signal}). Update LAB_PORTAL_BASE_URL or refresh auth storage state before running smoke checks.`
    );
  }
}
