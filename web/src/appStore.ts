export interface PublicAppStoreEnvironment {
  PUBLIC_NINA_APP_STORE_ID?: string;
}

export interface AppStoreListing {
  appStoreURL?: string;
  isPublished: boolean;
}

const placeholderPattern =
  /(replace|placeholder|example|todo|tbd|preencher|definir|\$\(|<[^>]+>)/i;
const appStoreIDPattern = /^[1-9][0-9]{5,}$/;

function clean(value: string | undefined): string | undefined {
  const normalized = value?.trim();
  if (!normalized || placeholderPattern.test(normalized)) return undefined;
  return normalized;
}

export function resolveAppStoreListing(
  environment: PublicAppStoreEnvironment,
): AppStoreListing {
  const appStoreID = clean(environment.PUBLIC_NINA_APP_STORE_ID);
  const isPublished = Boolean(appStoreID && appStoreIDPattern.test(appStoreID));

  return {
    appStoreURL: isPublished
      ? `https://apps.apple.com/br/app/id${appStoreID}`
      : undefined,
    isPublished,
  };
}

const buildEnvironment = (
  import.meta as ImportMeta & { readonly env?: PublicAppStoreEnvironment }
).env ?? {};

export const appStoreListing = resolveAppStoreListing(buildEnvironment);
