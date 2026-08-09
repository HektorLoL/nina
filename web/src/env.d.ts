/// <reference path="../.astro/types.d.ts" />
/// <reference types="@cloudflare/workers-types" />

interface ImportMetaEnv {
  readonly PUBLIC_NINA_APP_STORE_ID?: string;
  readonly PUBLIC_NINA_LEGAL_ENTITY_NAME?: string;
  readonly PUBLIC_NINA_LEGAL_ENTITY_DOCUMENT?: string;
  readonly PUBLIC_NINA_PRIVACY_CONTACT_EMAIL?: string;
  readonly PUBLIC_NINA_DPO_NAME?: string;
  readonly PUBLIC_NINA_DPO_CONTACT_EMAIL?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
