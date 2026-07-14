export function resolveStorageStatePath(environment: NodeJS.ProcessEnv): string | undefined {
  const candidate = environment.PW_STORAGE_STATE_PATH?.trim();
  return candidate ? candidate : undefined;
}

export function resolvePortalBaseUrl(environment: NodeJS.ProcessEnv): string | undefined {
  const candidate = environment.LAB_PORTAL_BASE_URL?.trim();
  return candidate ? candidate : undefined;
}
