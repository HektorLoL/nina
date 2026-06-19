import {
  Environment,
  SignedDataVerifier,
} from "npm:@apple/app-store-server-library@3.1.0";
import { Buffer } from "node:buffer";
import type { JWSTransactionDecodedPayload } from "npm:@apple/app-store-server-library@3.1.0/dist/models/JWSTransactionDecodedPayload";
import type { JWSRenewalInfoDecodedPayload } from "npm:@apple/app-store-server-library@3.1.0/dist/models/JWSRenewalInfoDecodedPayload";
import type { ResponseBodyV2DecodedPayload } from "npm:@apple/app-store-server-library@3.1.0/dist/models/ResponseBodyV2DecodedPayload";

export type PremiumSubscriptionStatus =
  | "inactive"
  | "active"
  | "grace_period"
  | "billing_retry"
  | "expired"
  | "revoked";

export type PremiumEntitlementResponse = {
  is_active: boolean;
  status: PremiumSubscriptionStatus;
  product_id: string | null;
  expires_at: string | null;
  will_renew: boolean | null;
  environment: string | null;
  original_transaction_id: string | null;
  latest_transaction_id: string | null;
  last_verified_at: string | null;
};

const defaultBundleID = "com.heitor.nina";
const defaultPremiumProductIDs = [
  "com.heitor.nina.premium.monthly",
  "com.heitor.nina.premium.yearly",
];
const appleRootCertificateURLs = [
  "https://www.apple.com/appleca/AppleIncRootCertificate.cer",
  "https://www.apple.com/certificateauthority/AppleRootCA-G2.cer",
  "https://www.apple.com/certificateauthority/AppleRootCA-G3.cer",
];

let rootCertificatesPromise: Promise<Buffer[]> | undefined;

export function allowedPremiumProductIDs(): string[] {
  const configured = Deno.env.get("NINA_PREMIUM_PRODUCT_IDS") ?? "";
  const ids = configured
    .split(/[\s,;]+/)
    .map((value) => value.trim())
    .filter(Boolean);

  return ids.length > 0 ? ids : defaultPremiumProductIDs;
}

export function appBundleID(): string {
  return Deno.env.get("NINA_APP_BUNDLE_ID")?.trim() || defaultBundleID;
}

export function jsonResponse(body: unknown, status = 200): Response {
  return Response.json(body, {
    status,
    headers: { "Cache-Control": "no-store" },
  });
}

export function parseConfiguredKey(variable: string, fallback: string): string {
  const configured = Deno.env.get(variable);
  if (configured) {
    try {
      const parsed = JSON.parse(configured) as Record<string, string>;
      if (parsed.default) return parsed.default;
      const first = Object.values(parsed).find(Boolean);
      if (first) return first;
    } catch {
      if (configured.length > 20) return configured;
    }
  }
  return Deno.env.get(fallback) ?? "";
}

export function isUUID(value: unknown): value is string {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value);
}

export function isPremiumSyncRequest(value: unknown): value is {
  signed_transaction_info: string;
  source?: string;
} {
  if (!value || typeof value !== "object") return false;
  const body = value as Record<string, unknown>;
  return typeof body.signed_transaction_info === "string" &&
    body.signed_transaction_info.split(".").length === 3 &&
    (body.source === undefined || typeof body.source === "string");
}

export function isAppStoreNotificationRequest(value: unknown): value is {
  signedPayload: string;
} {
  if (!value || typeof value !== "object") return false;
  const body = value as Record<string, unknown>;
  return typeof body.signedPayload === "string" &&
    body.signedPayload.split(".").length === 3;
}

export function mapAppleSubscriptionStatus(
  transaction: Pick<JWSTransactionDecodedPayload, "expiresDate" | "revocationDate">,
  renewal?: Pick<JWSRenewalInfoDecodedPayload, "gracePeriodExpiresDate" | "isInBillingRetryPeriod">,
  appleStatus?: number,
  now = Date.now(),
): PremiumSubscriptionStatus {
  if (transaction.revocationDate) return "revoked";

  switch (appleStatus) {
    case 1:
      return "active";
    case 2:
      return "expired";
    case 3:
      return "billing_retry";
    case 4:
      return "grace_period";
    case 5:
      return "revoked";
  }

  if (renewal?.gracePeriodExpiresDate && renewal.gracePeriodExpiresDate > now) {
    return "grace_period";
  }

  if (renewal?.isInBillingRetryPeriod) {
    return "billing_retry";
  }

  if (transaction.expiresDate && transaction.expiresDate <= now) {
    return "expired";
  }

  return "active";
}

export function entitlementFromSubscription(
  row: Record<string, unknown> | null | undefined,
): PremiumEntitlementResponse {
  if (!row) {
    return {
      is_active: false,
      status: "inactive",
      product_id: null,
      expires_at: null,
      will_renew: null,
      environment: null,
      original_transaction_id: null,
      latest_transaction_id: null,
      last_verified_at: null,
    };
  }

  return {
    is_active: row.is_active === true,
    status: typeof row.status === "string"
      ? row.status as PremiumSubscriptionStatus
      : "inactive",
    product_id: stringOrNull(row.product_id),
    expires_at: stringOrNull(row.expires_at),
    will_renew: typeof row.will_renew === "boolean" ? row.will_renew : null,
    environment: stringOrNull(row.environment),
    original_transaction_id: stringOrNull(row.original_transaction_id),
    latest_transaction_id: stringOrNull(row.transaction_id),
    last_verified_at: stringOrNull(row.last_verified_at),
  };
}

export async function verifyTransaction(
  signedTransactionInfo: string,
  preferredEnvironment?: string,
): Promise<JWSTransactionDecodedPayload> {
  return await verifyWithCandidates(
    preferredEnvironment,
    (verifier) => verifier.verifyAndDecodeTransaction(signedTransactionInfo),
  );
}

export async function verifyRenewalInfo(
  signedRenewalInfo: string,
  preferredEnvironment?: string,
): Promise<JWSRenewalInfoDecodedPayload> {
  return await verifyWithCandidates(
    preferredEnvironment,
    (verifier) => verifier.verifyAndDecodeRenewalInfo(signedRenewalInfo),
  );
}

export async function verifyNotification(
  signedPayload: string,
  preferredEnvironment?: string,
): Promise<ResponseBodyV2DecodedPayload> {
  return await verifyWithCandidates(
    preferredEnvironment,
    (verifier) => verifier.verifyAndDecodeNotification(signedPayload),
  );
}

export function assertTransactionMatchesNina(
  transaction: JWSTransactionDecodedPayload,
): void {
  if (transaction.bundleId !== appBundleID()) {
    throw new Error("invalid_bundle_id");
  }

  if (!transaction.productId || !allowedPremiumProductIDs().includes(transaction.productId)) {
    throw new Error("invalid_product_id");
  }

  if (transaction.type !== "Auto-Renewable Subscription") {
    throw new Error("invalid_product_type");
  }
}

export function buildSubscriptionUpsert(
  params: {
    userID: string | null;
    signedTransactionInfo: string;
    transaction: JWSTransactionDecodedPayload;
    signedRenewalInfo?: string | null;
    renewal?: JWSRenewalInfoDecodedPayload | null;
    notification?: ResponseBodyV2DecodedPayload | null;
    source: string;
  },
): Record<string, unknown> {
  const status = mapAppleSubscriptionStatus(
    params.transaction,
    params.renewal ?? undefined,
    statusNumber(params.notification?.data?.status),
  );
  const now = new Date().toISOString();

  return {
    original_transaction_id: requiredString(
      params.transaction.originalTransactionId,
      "missing_original_transaction_id",
    ),
    user_id: params.userID,
    app_account_token: isUUID(params.transaction.appAccountToken)
      ? params.transaction.appAccountToken
      : null,
    product_id: requiredString(params.transaction.productId, "missing_product_id"),
    environment: stringOrNull(params.transaction.environment)
      ?? stringOrNull(params.notification?.data?.environment)
      ?? "Unknown",
    status,
    is_active: status === "active" || status === "grace_period",
    transaction_id: requiredString(params.transaction.transactionId, "missing_transaction_id"),
    web_order_line_item_id: stringOrNull(params.transaction.webOrderLineItemId),
    purchased_at: isoDate(params.transaction.purchaseDate),
    original_purchase_at: isoDate(params.transaction.originalPurchaseDate),
    expires_at: isoDate(params.transaction.expiresDate),
    revoked_at: isoDate(params.transaction.revocationDate),
    revocation_reason: params.transaction.revocationReason == null
      ? null
      : String(params.transaction.revocationReason),
    grace_period_expires_at: isoDate(params.renewal?.gracePeriodExpiresDate),
    will_renew: params.renewal?.autoRenewStatus == null
      ? null
      : params.renewal.autoRenewStatus === 1,
    auto_renew_status: params.renewal?.autoRenewStatus == null
      ? null
      : params.renewal.autoRenewStatus === 1
      ? "on"
      : "off",
    auto_renew_product_id: stringOrNull(params.renewal?.autoRenewProductId),
    expiration_intent: params.renewal?.expirationIntent == null
      ? null
      : String(params.renewal.expirationIntent),
    signed_transaction_info: params.signedTransactionInfo,
    signed_renewal_info: params.signedRenewalInfo ?? null,
    raw_transaction: params.transaction,
    raw_renewal_info: params.renewal ?? {},
    latest_notification_type: stringOrNull(params.notification?.notificationType),
    latest_notification_subtype: stringOrNull(params.notification?.subtype),
    latest_notification_uuid: stringOrNull(params.notification?.notificationUUID),
    last_verified_at: now,
  };
}

export function buildTransactionLedgerUpsert(
  params: {
    userID: string | null;
    signedTransactionInfo: string;
    transaction: JWSTransactionDecodedPayload;
    source: string;
  },
): Record<string, unknown> {
  return {
    transaction_id: requiredString(params.transaction.transactionId, "missing_transaction_id"),
    original_transaction_id: requiredString(
      params.transaction.originalTransactionId,
      "missing_original_transaction_id",
    ),
    user_id: params.userID,
    app_account_token: isUUID(params.transaction.appAccountToken)
      ? params.transaction.appAccountToken
      : null,
    product_id: requiredString(params.transaction.productId, "missing_product_id"),
    environment: stringOrNull(params.transaction.environment) ?? "Unknown",
    product_type: stringOrNull(params.transaction.type),
    ownership_type: stringOrNull(params.transaction.inAppOwnershipType),
    source: params.source,
    purchased_at: isoDate(params.transaction.purchaseDate),
    expires_at: isoDate(params.transaction.expiresDate),
    revoked_at: isoDate(params.transaction.revocationDate),
    signed_transaction_info: params.signedTransactionInfo,
    payload: params.transaction,
  };
}

function configuredEnvironment(): Environment | null {
  const value = Deno.env.get("NINA_APP_STORE_ENVIRONMENT")?.trim().toLowerCase();
  switch (value) {
    case "production":
      return Environment.PRODUCTION;
    case "sandbox":
      return Environment.SANDBOX;
    case "xcode":
      return Environment.XCODE;
    case "localtesting":
    case "local_testing":
      return Environment.LOCAL_TESTING;
    default:
      return null;
  }
}

function environmentFromString(value?: string): Environment | null {
  switch (value) {
    case Environment.PRODUCTION:
      return Environment.PRODUCTION;
    case Environment.SANDBOX:
      return Environment.SANDBOX;
    case Environment.XCODE:
      return Environment.XCODE;
    case Environment.LOCAL_TESTING:
      return Environment.LOCAL_TESTING;
    default:
      return null;
  }
}

async function verifyWithCandidates<T>(
  preferredEnvironment: string | undefined,
  operation: (verifier: SignedDataVerifier) => Promise<T>,
): Promise<T> {
  let lastError: unknown;
  for (const environment of candidateEnvironments(preferredEnvironment)) {
    try {
      return await operation(await verifierFor(environment));
    } catch (error) {
      lastError = error;
    }
  }

  throw lastError instanceof Error ? lastError : new Error("app_store_verification_failed");
}

function candidateEnvironments(preferredEnvironment?: string): Environment[] {
  const configured = configuredEnvironment();
  if (configured) return [configured];

  const preferred = environmentFromString(preferredEnvironment);
  const candidates = [
    preferred,
    Environment.XCODE,
    Environment.SANDBOX,
    Environment.PRODUCTION,
    Environment.LOCAL_TESTING,
  ].filter((environment): environment is Environment => environment != null);

  return Array.from(new Set(candidates));
}

async function verifierFor(environment: Environment): Promise<SignedDataVerifier> {
  const appAppleId = Number(Deno.env.get("NINA_APP_APPLE_ID") ?? "");
  if (environment === Environment.PRODUCTION && (!Number.isFinite(appAppleId) || appAppleId <= 0)) {
    throw new Error("app_apple_id_required");
  }

  const enableOnlineChecks =
    (Deno.env.get("NINA_APP_STORE_ONLINE_CHECKS") ?? "true").toLowerCase() !== "false";

  return new SignedDataVerifier(
    await loadAppleRootCertificates(),
    enableOnlineChecks,
    environment,
    appBundleID(),
    environment === Environment.PRODUCTION ? appAppleId : undefined,
  );
}

async function loadAppleRootCertificates(): Promise<Buffer[]> {
  rootCertificatesPromise ??= loadConfiguredRootCertificates() ??
    Promise.all(
      appleRootCertificateURLs.map(async (url) => {
        const response = await fetch(url);
        if (!response.ok) throw new Error("apple_root_certificate_unavailable");
        return Buffer.from(await response.arrayBuffer());
      }),
    );

  return await rootCertificatesPromise;
}

function loadConfiguredRootCertificates(): Promise<Buffer[]> | undefined {
  const configured = Deno.env.get("APPLE_ROOT_CA_PEMS");
  if (!configured) return undefined;

  const pemBlocks = configured
    .split(/(?=-----BEGIN CERTIFICATE-----)/)
    .map((block) => block.trim())
    .filter(Boolean);

  if (pemBlocks.length === 0) return undefined;
  return Promise.resolve(pemBlocks.map((pem) => Buffer.from(pem)));
}

function statusNumber(value: unknown): number | undefined {
  return typeof value === "number" ? value : undefined;
}

function isoDate(value: unknown): string | null {
  return typeof value === "number" && Number.isFinite(value)
    ? new Date(value).toISOString()
    : null;
}

function stringOrNull(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function requiredString(value: unknown, errorCode: string): string {
  const string = stringOrNull(value);
  if (!string) throw new Error(errorCode);
  return string;
}
