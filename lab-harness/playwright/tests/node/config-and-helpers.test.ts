import assert from 'node:assert/strict';
import path from 'node:path';
import test from 'node:test';
import { pathToFileURL } from 'node:url';
import { detectInteractiveAuthSignal } from '../../src/portal-helpers';
import { resolvePortalBaseUrl, resolveStorageStatePath } from '../../src/config-helpers';

test('resolveStorageStatePath returns undefined when not configured', () => {
  const result = resolveStorageStatePath({});
  assert.equal(result, undefined);
});

test('resolveStorageStatePath trims configured value', () => {
  const result = resolveStorageStatePath({ PW_STORAGE_STATE_PATH: '  .auth/state.json  ' });
  assert.equal(result, '.auth/state.json');
});

test('resolvePortalBaseUrl trims configured value', () => {
  const result = resolvePortalBaseUrl({ LAB_PORTAL_BASE_URL: '  https://contoso.crm.dynamics.com  ' });
  assert.equal(result, 'https://contoso.crm.dynamics.com');
});

test('detectInteractiveAuthSignal identifies account picker and sign-in prompts', () => {
  assert.equal(detectInteractiveAuthSignal('Pick an account to continue'), 'pick an account');
  assert.equal(detectInteractiveAuthSignal('Please Sign in to your account now'), 'sign in to your account');
  assert.equal(detectInteractiveAuthSignal('Portal dashboard ready'), undefined);
});

test('playwright config reads storage state from environment', async () => {
  process.env.PW_STORAGE_STATE_PATH = '.auth/state.json';
  const configPath = pathToFileURL(path.resolve('playwright.config.ts')).href + `?cacheBust=${Date.now()}`;
  const loaded = await import(configPath);
  assert.equal(loaded.default.use.storageState, '.auth/state.json');
  delete process.env.PW_STORAGE_STATE_PATH;
});
