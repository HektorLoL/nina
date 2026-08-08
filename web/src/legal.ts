export interface PublicLegalEnvironment {
  PUBLIC_NINA_LEGAL_ENTITY_NAME?: string;
  PUBLIC_NINA_LEGAL_ENTITY_DOCUMENT?: string;
  PUBLIC_NINA_PRIVACY_CONTACT_EMAIL?: string;
  PUBLIC_NINA_DPO_NAME?: string;
  PUBLIC_NINA_DPO_CONTACT_EMAIL?: string;
}

export interface LegalIdentity {
  legalEntityName?: string;
  legalEntityDocument?: string;
  privacyContactEmail: string;
  dpoName?: string;
  dpoContactEmail?: string;
  isProductionComplete: boolean;
}

const fallbackContactEmail = "oi@ninai.app";
const placeholderPattern =
  /(replace|placeholder|example|todo|tbd|preencher|definir|\$\(|<[^>]+>)/i;
const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function clean(value: string | undefined): string | undefined {
  const normalized = value?.trim();
  if (!normalized || placeholderPattern.test(normalized)) return undefined;
  return normalized;
}

function cleanEmail(value: string | undefined): string | undefined {
  const normalized = clean(value)?.toLowerCase();
  return normalized && emailPattern.test(normalized) ? normalized : undefined;
}

export function resolveLegalIdentity(
  environment: PublicLegalEnvironment,
): LegalIdentity {
  const legalEntityName = clean(environment.PUBLIC_NINA_LEGAL_ENTITY_NAME);
  const legalEntityDocument = clean(
    environment.PUBLIC_NINA_LEGAL_ENTITY_DOCUMENT,
  );
  const privacyContactEmail = cleanEmail(
    environment.PUBLIC_NINA_PRIVACY_CONTACT_EMAIL,
  ) ?? fallbackContactEmail;
  const dpoName = clean(environment.PUBLIC_NINA_DPO_NAME);
  const dpoContactEmail = cleanEmail(
    environment.PUBLIC_NINA_DPO_CONTACT_EMAIL,
  );

  return {
    legalEntityName,
    legalEntityDocument,
    privacyContactEmail,
    dpoName,
    dpoContactEmail,
    isProductionComplete: Boolean(
      legalEntityName &&
        legalEntityDocument &&
        privacyContactEmail !== fallbackContactEmail &&
        dpoName &&
        dpoContactEmail,
    ),
  };
}

const buildEnvironment = (
  import.meta as ImportMeta & { readonly env?: PublicLegalEnvironment }
).env ?? {};

export const legalIdentity = resolveLegalIdentity(buildEnvironment);
