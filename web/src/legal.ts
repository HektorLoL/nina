export interface PublicLegalEnvironment {
  PUBLIC_NINA_LEGAL_ENTITY_NAME?: string;
  PUBLIC_NINA_LEGAL_ENTITY_DOCUMENT?: string;
  PUBLIC_NINA_LEGAL_ENTITY_ADDRESS?: string;
  PUBLIC_NINA_PRIVACY_CONTACT_EMAIL?: string;
  PUBLIC_NINA_REPORT_CONTACT_EMAIL?: string;
  PUBLIC_NINA_DPO_NAME?: string;
  PUBLIC_NINA_DPO_CONTACT_EMAIL?: string;
}

export type LegalEntityKind = "company" | "individual";
export type LegalDocumentLabel = "CNPJ" | "CPF" | "Documento";

export interface LegalIdentity {
  legalEntityName?: string;
  legalEntityDocument?: string;
  legalEntityAddress?: string;
  legalEntityKind?: LegalEntityKind;
  documentLabel: LegalDocumentLabel;
  privacyContactEmail: string;
  reportContactEmail: string;
  dpoName?: string;
  dpoContactEmail?: string;
  dpoIsIndependent: boolean;
  isProductionComplete: boolean;
  isLaunchReady: boolean;
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

function entityKind(
  document: string | undefined,
): LegalEntityKind | undefined {
  const digits = document?.replace(/\D/g, "") ?? "";
  if (digits.length === 14) return "company";
  if (digits.length === 11) return "individual";
  return undefined;
}

function documentLabelFor(
  kind: LegalEntityKind | undefined,
): LegalDocumentLabel {
  if (kind === "company") return "CNPJ";
  if (kind === "individual") return "CPF";
  return "Documento";
}

function comparableName(value: string): string {
  return value
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .toLowerCase()
    .replace(/[^\p{Letter}\p{Number}]+/gu, " ")
    .trim();
}

// A DPO who cannot be told apart from the controller never counts as independent.
function isIndependentDPO(
  dpoName: string | undefined,
  legalEntityName: string | undefined,
): boolean {
  if (!dpoName || !legalEntityName) return false;
  return comparableName(dpoName) !== comparableName(legalEntityName);
}

export function resolveLegalIdentity(
  environment: PublicLegalEnvironment,
): LegalIdentity {
  const legalEntityName = clean(environment.PUBLIC_NINA_LEGAL_ENTITY_NAME);
  const legalEntityDocument = clean(
    environment.PUBLIC_NINA_LEGAL_ENTITY_DOCUMENT,
  );
  const legalEntityAddress = clean(
    environment.PUBLIC_NINA_LEGAL_ENTITY_ADDRESS,
  );
  const legalEntityKind = entityKind(legalEntityDocument);
  const privacyContactEmail = cleanEmail(
    environment.PUBLIC_NINA_PRIVACY_CONTACT_EMAIL,
  ) ?? fallbackContactEmail;
  const reportContactEmail = cleanEmail(
    environment.PUBLIC_NINA_REPORT_CONTACT_EMAIL,
  ) ?? privacyContactEmail;
  const dpoName = clean(environment.PUBLIC_NINA_DPO_NAME);
  const dpoContactEmail = cleanEmail(
    environment.PUBLIC_NINA_DPO_CONTACT_EMAIL,
  );
  const dpoIsIndependent = isIndependentDPO(dpoName, legalEntityName);
  const isProductionComplete = Boolean(
    legalEntityName &&
      legalEntityDocument &&
      privacyContactEmail !== fallbackContactEmail &&
      dpoName &&
      dpoContactEmail,
  );

  return {
    legalEntityName,
    legalEntityDocument,
    legalEntityAddress,
    legalEntityKind,
    documentLabel: documentLabelFor(legalEntityKind),
    privacyContactEmail,
    reportContactEmail,
    dpoName,
    dpoContactEmail,
    dpoIsIndependent,
    isProductionComplete,
    isLaunchReady: isProductionComplete &&
      legalEntityKind === "company" &&
      Boolean(legalEntityAddress) &&
      dpoIsIndependent,
  };
}

const buildEnvironment = (
  import.meta as ImportMeta & { readonly env?: PublicLegalEnvironment }
).env ?? {};

export const legalIdentity = resolveLegalIdentity(buildEnvironment);
