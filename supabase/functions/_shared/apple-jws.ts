import * as x509 from "npm:@peculiar/x509@1.14.3";

// Apple's own library leans on node:crypto's X509Certificate, which the Supabase
// edge runtime only stubs; WebCrypto is the one certificate path every runtime has.

export const AppleEnvironment = {
  PRODUCTION: "Production",
  SANDBOX: "Sandbox",
  XCODE: "Xcode",
  LOCAL_TESTING: "LocalTesting",
} as const;

export type AppleEnvironment =
  (typeof AppleEnvironment)[keyof typeof AppleEnvironment];

export type AppleVerificationStatus =
  | "verification_failure"
  | "invalid_app_identifier"
  | "invalid_environment"
  | "invalid_chain_length"
  | "invalid_certificate"
  | "failure";

export class AppleVerificationError extends Error {
  status: AppleVerificationStatus;

  constructor(status: AppleVerificationStatus, cause?: unknown) {
    super(status, cause === undefined ? undefined : { cause });
    this.name = "AppleVerificationError";
    this.status = status;
  }
}

export interface AppleVerifierConfiguration {
  rootCertificates: Uint8Array[];
  environment: AppleEnvironment;
  bundleID: string;
  appAppleID?: number;
  useCurrentDate: boolean;
}

type Payload = Record<string, unknown>;

const leafMarkerOID = "1.2.840.113635.100.6.11.1";
const intermediateMarkerOID = "1.2.840.113635.100.6.2.1";
const ecdsaP256 = { name: "ECDSA", namedCurve: "P-256" } as const;
const ecdsaSHA256 = { name: "ECDSA", hash: "SHA-256" } as const;

function base64URLToBytes(value: string): Uint8Array {
  const base64 = value.replace(/-/g, "+").replace(/_/g, "/") +
    "=".repeat((4 - (value.length % 4)) % 4);
  return Uint8Array.from(atob(base64), (character) => character.charCodeAt(0));
}

// TypeScript's BufferSource wants a plain ArrayBuffer; a view over a shared buffer is refused.
function asArrayBuffer(view: Uint8Array): ArrayBuffer {
  return view.buffer.slice(
    view.byteOffset,
    view.byteOffset + view.byteLength,
  ) as ArrayBuffer;
}

function decodeJSONSegment(segment: string): Payload {
  const text = new TextDecoder().decode(base64URLToBytes(segment));
  const value: unknown = JSON.parse(text);
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new AppleVerificationError("failure");
  }
  return value as Payload;
}

function record(value: unknown): Payload | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Payload
    : null;
}

function signedDate(payload: Payload): Date {
  const value = payload.signedDate;
  return typeof value === "number" && Number.isFinite(value)
    ? new Date(value)
    : new Date();
}

function parseCertificate(source: Uint8Array | string): x509.X509Certificate {
  try {
    return typeof source === "string"
      ? new x509.X509Certificate(source)
      : new x509.X509Certificate(asArrayBuffer(source));
  } catch (error) {
    throw new AppleVerificationError("invalid_certificate", error);
  }
}

function withinValidity(
  certificate: x509.X509Certificate,
  date: Date,
): boolean {
  return certificate.notBefore.getTime() <= date.getTime() &&
    date.getTime() <= certificate.notAfter.getTime();
}

async function signedBy(
  certificate: x509.X509Certificate,
  issuer: x509.X509Certificate,
): Promise<boolean> {
  if (certificate.issuer !== issuer.subject) return false;
  try {
    return await certificate.verify({
      publicKey: issuer.publicKey,
      signatureOnly: true,
    });
  } catch {
    return false;
  }
}

// Mirrors Apple's chain rules: a trusted root signs the intermediate, the intermediate
// is a CA carrying Apple's intermediate marker, the leaf carries Apple's receipt marker.
export async function verifyAppleCertificateChain(
  rootCertificates: Uint8Array[],
  leaf: x509.X509Certificate,
  intermediate: x509.X509Certificate,
  effectiveDate: Date,
): Promise<CryptoKey> {
  let root: x509.X509Certificate | null = null;
  for (const candidate of rootCertificates) {
    const parsed = parseCertificate(candidate);
    if (await signedBy(intermediate, parsed)) {
      root = parsed;
      break;
    }
  }

  const chainIsValid = root !== null &&
    await signedBy(leaf, intermediate) &&
    intermediate.getExtension(x509.BasicConstraintsExtension)?.ca === true &&
    leaf.getExtension(leafMarkerOID) !== null &&
    intermediate.getExtension(intermediateMarkerOID) !== null;

  if (!chainIsValid || root === null) {
    throw new AppleVerificationError("verification_failure");
  }

  for (const certificate of [leaf, intermediate, root]) {
    if (!withinValidity(certificate, effectiveDate)) {
      throw new AppleVerificationError("verification_failure");
    }
  }

  try {
    return await crypto.subtle.importKey(
      "spki",
      leaf.publicKey.rawData,
      ecdsaP256,
      false,
      ["verify"],
    );
  } catch (error) {
    throw new AppleVerificationError("verification_failure", error);
  }
}

export async function verifyAppleJWS(
  jws: string,
  configuration: AppleVerifierConfiguration,
): Promise<Payload> {
  const segments = jws.split(".");
  if (segments.length !== 3) {
    throw new AppleVerificationError("verification_failure");
  }

  let header: Payload;
  let payload: Payload;
  try {
    header = decodeJSONSegment(segments[0]);
    payload = decodeJSONSegment(segments[1]);
  } catch (error) {
    throw error instanceof AppleVerificationError
      ? error
      : new AppleVerificationError("verification_failure", error);
  }

  // Data from Xcode or local testing is not signed by the App Store; the caller must
  // have configured that environment explicitly, and the check stays with the caller.
  if (
    configuration.environment === AppleEnvironment.XCODE ||
    configuration.environment === AppleEnvironment.LOCAL_TESTING
  ) {
    return payload;
  }

  if (header.alg !== "ES256") {
    throw new AppleVerificationError("verification_failure");
  }

  const chain = header.x5c;
  if (
    !Array.isArray(chain) || chain.length !== 3 ||
    !chain.every((entry) => typeof entry === "string")
  ) {
    throw new AppleVerificationError("invalid_chain_length");
  }

  const leaf = parseCertificate(chain[0]);
  const intermediate = parseCertificate(chain[1]);
  const effectiveDate = configuration.useCurrentDate
    ? new Date()
    : signedDate(payload);
  const leafKey = await verifyAppleCertificateChain(
    configuration.rootCertificates,
    leaf,
    intermediate,
    effectiveDate,
  );

  const signature = base64URLToBytes(segments[2]);
  const signedBytes = new TextEncoder().encode(
    `${segments[0]}.${segments[1]}`,
  );
  let signatureIsValid = false;
  try {
    signatureIsValid = signature.byteLength === 64 &&
      await crypto.subtle.verify(
        ecdsaSHA256,
        leafKey,
        asArrayBuffer(signature),
        asArrayBuffer(signedBytes),
      );
  } catch (error) {
    throw new AppleVerificationError("verification_failure", error);
  }
  if (!signatureIsValid) {
    throw new AppleVerificationError("verification_failure");
  }

  return payload;
}

export async function verifyAppleTransaction<T extends object>(
  signedTransactionInfo: string,
  configuration: AppleVerifierConfiguration,
): Promise<T> {
  const payload = await verifyAppleJWS(signedTransactionInfo, configuration);
  if (payload.bundleId !== configuration.bundleID) {
    throw new AppleVerificationError("invalid_app_identifier");
  }
  if (payload.environment !== configuration.environment) {
    throw new AppleVerificationError("invalid_environment");
  }
  return payload as unknown as T;
}

export async function verifyAppleRenewalInfo<T extends object>(
  signedRenewalInfo: string,
  configuration: AppleVerifierConfiguration,
): Promise<T> {
  const payload = await verifyAppleJWS(signedRenewalInfo, configuration);
  if (payload.environment !== configuration.environment) {
    throw new AppleVerificationError("invalid_environment");
  }
  return payload as unknown as T;
}

export async function verifyAppleNotification<T extends object>(
  signedPayload: string,
  configuration: AppleVerifierConfiguration,
): Promise<T> {
  const payload = await verifyAppleJWS(signedPayload, configuration);

  let appAppleID: unknown;
  let bundleID: unknown;
  let environment: unknown;
  const data = record(payload.data);
  const summary = record(payload.summary);
  const externalPurchaseToken = record(payload.externalPurchaseToken);
  const appData = record(payload.appData);
  if (data) {
    appAppleID = data.appAppleId;
    bundleID = data.bundleId;
    environment = data.environment;
  } else if (summary) {
    appAppleID = summary.appAppleId;
    bundleID = summary.bundleId;
    environment = summary.environment;
  } else if (externalPurchaseToken) {
    appAppleID = externalPurchaseToken.appAppleId;
    bundleID = externalPurchaseToken.bundleId;
    const externalPurchaseID = externalPurchaseToken.externalPurchaseId;
    environment = typeof externalPurchaseID === "string" &&
        externalPurchaseID.startsWith("SANDBOX")
      ? AppleEnvironment.SANDBOX
      : AppleEnvironment.PRODUCTION;
  } else if (appData) {
    appAppleID = appData.appAppleId;
    bundleID = appData.bundleId;
    environment = appData.environment;
  }

  if (
    bundleID !== configuration.bundleID ||
    (configuration.environment === AppleEnvironment.PRODUCTION &&
      appAppleID !== configuration.appAppleID)
  ) {
    throw new AppleVerificationError("invalid_app_identifier");
  }
  if (environment !== configuration.environment) {
    throw new AppleVerificationError("invalid_environment");
  }
  return payload as unknown as T;
}
