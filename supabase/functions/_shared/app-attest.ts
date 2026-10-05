// deno-lint-ignore no-import-prefix
import { p256, p384 } from "npm:@noble/curves@2.4.0/nist.js";
// deno-lint-ignore no-import-prefix
import * as x509 from "npm:@peculiar/x509@1.14.3";
import {
  mapAgeRange,
  type MappedAge,
  maxSignalJSONBytes,
  parseAgeSignalJSON,
} from "./age-assurance.ts";

// Apple's CA 1 signs device certificates with a P-384 key over SHA-256, which
// the edge runtime's WebCrypto refuses, so no chain link may go through it.

export type AppAttestMode = "production" | "development" | "insecure-local";
export type AppAttestEnvironment = "production" | "development";

export const appAttestAppID = "97PL8KQA8L.com.heitor.nina";
export const appAttestNonceOID = "1.2.840.113635.100.8.2";
export const insecureLocalKeyID = "insecure-local";
export const maxAgeSignalRequestBytes = 32 * 1_024;

export const appleAppAttestRootPEM = `-----BEGIN CERTIFICATE-----
MIICITCCAaegAwIBAgIQC/O+DvHN0uD7jG5yH2IXmDAKBggqhkjOPQQDAzBSMSYw
JAYDVQQDDB1BcHBsZSBBcHAgQXR0ZXN0YXRpb24gUm9vdCBDQTETMBEGA1UECgwK
QXBwbGUgSW5jLjETMBEGA1UECAwKQ2FsaWZvcm5pYTAeFw0yMDAzMTgxODMyNTNa
Fw00NTAzMTUwMDAwMDBaMFIxJjAkBgNVBAMMHUFwcGxlIEFwcCBBdHRlc3RhdGlv
biBSb290IENBMRMwEQYDVQQKDApBcHBsZSBJbmMuMRMwEQYDVQQIDApDYWxpZm9y
bmlhMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAERTHhmLW07ATaFQIEVwTtT4dyctdh
NbJhFs/Ii2FdCgAHGbpphY3+d8qjuDngIN3WVhQUBHAoMeQ/cLiP1sOUtgjqK9au
Yen1mMEvRq9Sk3Jm5X8U62H+xTD3FE9TgS41o0IwQDAPBgNVHRMBAf8EBTADAQH/
MB0GA1UdDgQWBBSskRBTM72+aEH/pwyp5frq5eWKoTAOBgNVHQ8BAf8EBAMCAQYw
CgYIKoZIzj0EAwMDaAAwZQIwQgFGnByvsiVbpTKwSga0kP0e8EeDS4+sQmTvb7vn
53O5+FRXgeLhpJ06ysC5PrOyAjEAp5U4xDgEgllF7En3VcE3iexZZtKeYnpqtijV
oyFraWVIyd/dganmrduC1bmTBGwD
-----END CERTIFICATE-----`;

const productionAAGUID = new Uint8Array([
  ...new TextEncoder().encode("appattest"),
  0,
  0,
  0,
  0,
  0,
  0,
  0,
]);
const developmentAAGUID = new TextEncoder().encode("appattestdevelop");
const loopbackHosts = new Set([
  "localhost",
  "127.0.0.1",
  "[::1]",
  "::1",
  "kong",
  "host.docker.internal",
]);

export class AppAttestError extends Error {
  constructor(readonly code: "app_attest_invalid") {
    super(code);
    this.name = "AppAttestError";
  }
}

function invalid(): never {
  throw new AppAttestError("app_attest_invalid");
}

function buffer(view: Uint8Array): ArrayBuffer {
  return view.buffer.slice(
    view.byteOffset,
    view.byteOffset + view.byteLength,
  ) as ArrayBuffer;
}

function concat(...parts: Uint8Array[]): Uint8Array {
  const total = parts.reduce((sum, part) => sum + part.byteLength, 0);
  const result = new Uint8Array(total);
  let offset = 0;
  for (const part of parts) {
    result.set(part, offset);
    offset += part.byteLength;
  }
  return result;
}

function sameBytes(left: Uint8Array, right: Uint8Array): boolean {
  if (left.byteLength !== right.byteLength) return false;
  let difference = 0;
  for (let index = 0; index < left.byteLength; index += 1) {
    difference |= left[index] ^ right[index];
  }
  return difference === 0;
}

export async function sha256(bytes: Uint8Array): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", buffer(bytes)));
}

export function decodeBase64(value: string): Uint8Array | null {
  if (!/^[A-Za-z0-9+/]*={0,2}$/.test(value) || value.length % 4 !== 0) {
    return null;
  }
  try {
    return Uint8Array.from(atob(value), (character) => character.charCodeAt(0));
  } catch {
    return null;
  }
}

export function decodeBase64URL(value: string): Uint8Array | null {
  if (!/^[A-Za-z0-9_-]*$/.test(value)) return null;
  const base64 = value.replaceAll("-", "+").replaceAll("_", "/") +
    "=".repeat((4 - (value.length % 4)) % 4);
  return decodeBase64(base64);
}

export function encodeBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

// Development and insecure-local attestations are refused unless the project
// itself is a loopback stack, so a misconfigured production cannot relax.
export function resolveAppAttestMode(
  rawMode: string | undefined,
  supabaseURL: string,
): AppAttestMode | null {
  const mode = rawMode?.trim();
  if (mode === "production") return "production";
  if (mode !== "development" && mode !== "insecure-local") return null;
  try {
    const url = new URL(supabaseURL);
    return url.protocol === "http:" && loopbackHosts.has(url.hostname)
      ? mode
      : null;
  } catch {
    return null;
  }
}

type CBORValue =
  | number
  | string
  | boolean
  | null
  | undefined
  | Uint8Array
  | CBORValue[]
  | Map<CBORValue, CBORValue>;

class CBORReader {
  offset = 0;
  constructor(private readonly bytes: Uint8Array) {}

  private byte(): number {
    if (this.offset >= this.bytes.byteLength) invalid();
    return this.bytes[this.offset++];
  }

  private length(additional: number): number {
    if (additional < 24) return additional;
    let size = 0;
    if (additional === 24) size = 1;
    else if (additional === 25) size = 2;
    else if (additional === 26) size = 4;
    else if (additional === 27) size = 8;
    else invalid();
    let value = 0;
    for (let index = 0; index < size; index += 1) {
      value = value * 256 + this.byte();
    }
    if (!Number.isSafeInteger(value)) invalid();
    return value;
  }

  private take(count: number): Uint8Array {
    if (count > this.bytes.byteLength - this.offset) invalid();
    const slice = this.bytes.slice(this.offset, this.offset + count);
    this.offset += count;
    return slice;
  }

  read(depth = 0): CBORValue {
    if (depth > 8) invalid();
    const initial = this.byte();
    const major = initial >> 5;
    const additional = initial & 0x1f;
    switch (major) {
      case 0:
        return this.length(additional);
      case 1:
        return -1 - this.length(additional);
      case 2:
        return this.take(this.length(additional));
      case 3:
        return new TextDecoder("utf-8", { fatal: true }).decode(
          this.take(this.length(additional)),
        );
      case 4: {
        const count = this.length(additional);
        if (count > 64) invalid();
        const items: CBORValue[] = [];
        for (let index = 0; index < count; index += 1) {
          items.push(this.read(depth + 1));
        }
        return items;
      }
      case 5: {
        const count = this.length(additional);
        if (count > 64) invalid();
        const map = new Map<CBORValue, CBORValue>();
        for (let index = 0; index < count; index += 1) {
          const key = this.read(depth + 1);
          map.set(key, this.read(depth + 1));
        }
        return map;
      }
      case 7:
        if (additional === 20) return false;
        if (additional === 21) return true;
        if (additional === 22) return null;
        if (additional === 23) return undefined;
        return invalid();
      default:
        return invalid();
    }
  }

  finish(): void {
    if (this.offset !== this.bytes.byteLength) invalid();
  }
}

export function decodeCBOR(bytes: Uint8Array): CBORValue {
  const reader = new CBORReader(bytes);
  const value = reader.read();
  reader.finish();
  return value;
}

function mapField(value: CBORValue, key: string): CBORValue {
  return value instanceof Map ? value.get(key) : undefined;
}

type DERNode = { tag: number; content: Uint8Array; next: number };

function readDER(bytes: Uint8Array, offset: number): DERNode {
  if (offset + 2 > bytes.byteLength) invalid();
  const tag = bytes[offset];
  let length = bytes[offset + 1];
  let cursor = offset + 2;
  if (length & 0x80) {
    const size = length & 0x7f;
    if (size === 0 || size > 2 || cursor + size > bytes.byteLength) invalid();
    length = 0;
    for (let index = 0; index < size; index += 1) {
      length = length * 256 + bytes[cursor + index];
    }
    cursor += size;
  }
  if (cursor + length > bytes.byteLength) invalid();
  return {
    tag,
    content: bytes.slice(cursor, cursor + length),
    next: cursor + length,
  };
}

function nonceFromExtension(value: Uint8Array): Uint8Array {
  const sequence = readDER(value, 0);
  if (sequence.tag !== 0x30 || sequence.next !== value.byteLength) invalid();
  const tagged = readDER(sequence.content, 0);
  if (tagged.tag !== 0xa1) invalid();
  const octets = readDER(tagged.content, 0);
  if (octets.tag !== 0x04 || octets.content.byteLength !== 32) invalid();
  return octets.content;
}

export function derSignatureToRaw(signature: Uint8Array): Uint8Array {
  const sequence = readDER(signature, 0);
  if (sequence.tag !== 0x30 || sequence.next !== signature.byteLength) {
    invalid();
  }
  const r = readDER(sequence.content, 0);
  const s = readDER(sequence.content, r.next);
  if (
    r.tag !== 0x02 || s.tag !== 0x02 || s.next !== sequence.content.byteLength
  ) invalid();

  const component = (integer: Uint8Array) => {
    let start = 0;
    while (start < integer.byteLength - 1 && integer[start] === 0) start += 1;
    const trimmed = integer.slice(start);
    if (trimmed.byteLength > 32) invalid();
    const padded = new Uint8Array(32);
    padded.set(trimmed, 32 - trimmed.byteLength);
    return padded;
  };
  return concat(component(r.content), component(s.content));
}

export async function registrationClientDataHash(
  challenge: Uint8Array,
  userID: string,
): Promise<Uint8Array> {
  return await sha256(
    concat(
      challenge,
      new TextEncoder().encode("register"),
      new TextEncoder().encode(userID.toLowerCase()),
    ),
  );
}

export async function assertionClientDataHash(
  challenge: Uint8Array,
  signalJSON: string,
): Promise<Uint8Array> {
  return await sha256(concat(challenge, new TextEncoder().encode(signalJSON)));
}

function withinValidity(certificate: x509.X509Certificate, now: Date): boolean {
  return certificate.notBefore.getTime() <= now.getTime() &&
    now.getTime() <= certificate.notAfter.getTime();
}

function hexBytes(value: string): Uint8Array {
  return Uint8Array.from(
    value.match(/../g) ?? [],
    (pair) => Number.parseInt(pair, 16),
  );
}

const certificateSignatureAlgorithms = [
  { identifier: hexBytes("300a06082a8648ce3d040302"), hash: "SHA-256" },
  { identifier: hexBytes("300a06082a8648ce3d040303"), hash: "SHA-384" },
] as const;

const certificateIssuerCurves = [
  {
    identifier: hexBytes("301306072a8648ce3d020106082a8648ce3d030107"),
    curve: p256,
  },
  {
    identifier: hexBytes("301006072a8648ce3d020106052b81040022"),
    curve: p384,
  },
] as const;

type CertificateParts = {
  signedBytes: Uint8Array;
  signatureAlgorithm: Uint8Array;
  signature: Uint8Array;
  publicKeyAlgorithm: Uint8Array;
  publicKey: Uint8Array;
};

function bitStringBytes(content: Uint8Array): Uint8Array {
  if (content.byteLength < 2 || content[0] !== 0) invalid();
  return content.slice(1);
}

function certificateParts(der: Uint8Array): CertificateParts {
  const certificate = readDER(der, 0);
  if (certificate.tag !== 0x30 || certificate.next !== der.byteLength) {
    invalid();
  }
  const body = certificate.content;
  const tbs = readDER(body, 0);
  const algorithm = readDER(body, tbs.next);
  const signature = readDER(body, algorithm.next);
  if (
    tbs.tag !== 0x30 || algorithm.tag !== 0x30 || signature.tag !== 0x03 ||
    signature.next !== body.byteLength
  ) invalid();
  const signatureAlgorithm = body.slice(tbs.next, algorithm.next);

  const fields = tbs.content;
  let field = readDER(fields, 0);
  if (field.tag === 0xa0) field = readDER(fields, field.next);
  if (field.tag !== 0x02) invalid();
  const innerAlgorithm = readDER(fields, field.next);
  if (
    innerAlgorithm.tag !== 0x30 ||
    !sameBytes(
      fields.slice(field.next, innerAlgorithm.next),
      signatureAlgorithm,
    )
  ) invalid();
  let cursor = innerAlgorithm.next;
  for (let index = 0; index < 3; index += 1) {
    const name = readDER(fields, cursor);
    if (name.tag !== 0x30) invalid();
    cursor = name.next;
  }
  const subjectPublicKeyInfo = readDER(fields, cursor);
  if (subjectPublicKeyInfo.tag !== 0x30) invalid();
  const keyAlgorithm = readDER(subjectPublicKeyInfo.content, 0);
  const key = readDER(subjectPublicKeyInfo.content, keyAlgorithm.next);
  if (
    keyAlgorithm.tag !== 0x30 || key.tag !== 0x03 ||
    key.next !== subjectPublicKeyInfo.content.byteLength
  ) invalid();

  return {
    signedBytes: body.slice(0, tbs.next),
    signatureAlgorithm,
    signature: bitStringBytes(signature.content),
    publicKeyAlgorithm: subjectPublicKeyInfo.content.slice(
      0,
      keyAlgorithm.next,
    ),
    publicKey: bitStringBytes(key.content),
  };
}

// A link holds only for ECDSA over SHA-256 or SHA-384 by a P-256 or P-384
// issuer, checked on the certificate's own DER; a high-S signature is valid
// X.509 and is verified as it arrived.
export async function certificateSignedBy(
  certificate: Uint8Array,
  issuer: Uint8Array,
): Promise<boolean> {
  try {
    const signed = certificateParts(certificate);
    const signer = certificateParts(issuer);
    const algorithm = certificateSignatureAlgorithms.find((candidate) =>
      sameBytes(candidate.identifier, signed.signatureAlgorithm)
    );
    const issuerCurve = certificateIssuerCurves.find((candidate) =>
      sameBytes(candidate.identifier, signer.publicKeyAlgorithm)
    );
    if (!algorithm || !issuerCurve) return false;
    const digest = new Uint8Array(
      await crypto.subtle.digest(algorithm.hash, buffer(signed.signedBytes)),
    );
    return issuerCurve.curve.verify(
      signed.signature,
      digest,
      signer.publicKey,
      { prehash: false, lowS: false, format: "der" },
    );
  } catch {
    return false;
  }
}

async function signedBy(
  certificate: x509.X509Certificate,
  issuer: x509.X509Certificate,
): Promise<boolean> {
  if (certificate.issuer !== issuer.subject) return false;
  return await certificateSignedBy(
    new Uint8Array(certificate.rawData),
    new Uint8Array(issuer.rawData),
  );
}

export function rootCertificatesFrom(
  override: string | undefined,
): x509.X509Certificate[] {
  const source = override?.trim() ? override : appleAppAttestRootPEM;
  return source
    .split(/(?=-----BEGIN CERTIFICATE-----)/)
    .map((pem) => pem.trim())
    .filter(Boolean)
    .map((pem) => new x509.X509Certificate(pem));
}

export type VerifiedAttestation = {
  publicKeySPKI: string;
  environment: AppAttestEnvironment;
};

// A device key is accepted only when every Apple attestation check holds for
// this challenge, this account and the mode the server runs in.
export async function verifyAttestation(input: {
  attestation: Uint8Array;
  keyID: string;
  clientDataHash: Uint8Array;
  mode: AppAttestEnvironment;
  rootCertificates: x509.X509Certificate[];
  now: Date;
  appID?: string;
}): Promise<VerifiedAttestation> {
  const keyIDBytes = decodeBase64(input.keyID);
  if (!keyIDBytes || keyIDBytes.byteLength !== 32) invalid();

  const object = decodeCBOR(input.attestation);
  if (mapField(object, "fmt") !== "apple-appattest") invalid();
  const statement = mapField(object, "attStmt");
  const x5c = mapField(statement, "x5c");
  const authData = mapField(object, "authData");
  if (
    !Array.isArray(x5c) || x5c.length < 2 ||
    !x5c.every((entry) => entry instanceof Uint8Array) ||
    !(authData instanceof Uint8Array)
  ) invalid();

  let credential: x509.X509Certificate;
  let intermediate: x509.X509Certificate;
  try {
    credential = new x509.X509Certificate(buffer(x5c[0] as Uint8Array));
    intermediate = new x509.X509Certificate(buffer(x5c[1] as Uint8Array));
  } catch {
    return invalid();
  }

  let root: x509.X509Certificate | null = null;
  for (const candidate of input.rootCertificates) {
    if (await signedBy(intermediate, candidate)) {
      root = candidate;
      break;
    }
  }
  if (
    !root ||
    !(await signedBy(credential, intermediate)) ||
    intermediate.getExtension(x509.BasicConstraintsExtension)?.ca !== true ||
    ![credential, intermediate, root].every((certificate) =>
      withinValidity(certificate, input.now)
    )
  ) invalid();

  const nonce = await sha256(concat(authData, input.clientDataHash));
  const extension = credential.getExtension(appAttestNonceOID);
  if (
    !extension ||
    !sameBytes(nonceFromExtension(new Uint8Array(extension.value)), nonce)
  ) invalid();

  let credentialKey: CryptoKey;
  try {
    credentialKey = await crypto.subtle.importKey(
      "spki",
      credential.publicKey.rawData,
      { name: "ECDSA", namedCurve: "P-256" },
      true,
      ["verify"],
    );
  } catch {
    return invalid();
  }
  const point = new Uint8Array(
    await crypto.subtle.exportKey("raw", credentialKey),
  );
  if (!sameBytes(await sha256(point), keyIDBytes)) invalid();

  if (authData.byteLength < 55) invalid();
  const rpIDHash = authData.slice(0, 32);
  const counter = new DataView(buffer(authData.slice(33, 37))).getUint32(0);
  const aaguid = authData.slice(37, 53);
  const credentialIDLength = new DataView(buffer(authData.slice(53, 55)))
    .getUint16(0);
  if (authData.byteLength < 55 + credentialIDLength) invalid();
  const credentialID = authData.slice(55, 55 + credentialIDLength);

  if (
    !sameBytes(
      rpIDHash,
      await sha256(new TextEncoder().encode(input.appID ?? appAttestAppID)),
    ) ||
    counter !== 0 ||
    !sameBytes(credentialID, keyIDBytes)
  ) invalid();

  const expectedAAGUID = input.mode === "production"
    ? productionAAGUID
    : developmentAAGUID;
  if (!sameBytes(aaguid, expectedAAGUID)) invalid();

  return {
    publicKeySPKI: encodeBase64(new Uint8Array(credential.publicKey.rawData)),
    environment: input.mode,
  };
}

export async function verifyAssertion(input: {
  assertion: Uint8Array;
  publicKeySPKI: string;
  storedCounter: number;
  clientDataHash: Uint8Array;
}): Promise<{ counter: number }> {
  const object = decodeCBOR(input.assertion);
  const signature = mapField(object, "signature");
  const authenticatorData = mapField(object, "authenticatorData");
  if (
    !(signature instanceof Uint8Array) ||
    !(authenticatorData instanceof Uint8Array) ||
    authenticatorData.byteLength < 37
  ) invalid();

  const spki = decodeBase64(input.publicKeySPKI);
  if (!spki) invalid();
  let key: CryptoKey;
  try {
    key = await crypto.subtle.importKey(
      "spki",
      buffer(spki),
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["verify"],
    );
  } catch {
    return invalid();
  }

  const nonce = await sha256(concat(authenticatorData, input.clientDataHash));
  const valid = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    buffer(derSignatureToRaw(signature)),
    buffer(nonce),
  );
  if (!valid) invalid();

  if (
    !sameBytes(
      authenticatorData.slice(0, 32),
      await sha256(new TextEncoder().encode(appAttestAppID)),
    )
  ) invalid();

  const counter = new DataView(buffer(authenticatorData.slice(33, 37)))
    .getUint32(0);
  if (counter <= input.storedCounter) invalid();
  return { counter };
}

export type StoredAttestKey = {
  public_key_spki: string;
  counter: number;
  environment: AppAttestEnvironment;
};

export type RecordedAgeSignal = {
  status: string;
  band: string | null;
  changed: boolean;
  photo_cleanup_required: boolean;
};

export class AgeSignalRejected extends Error {
  constructor() {
    super("age_signal_rejected");
    this.name = "AgeSignalRejected";
  }
}

export class AgeSignalRateLimited extends Error {
  constructor() {
    super("rate_limited");
    this.name = "AgeSignalRateLimited";
  }
}

export interface AgeSignalBackend {
  authenticatedUserID(accessToken: string): Promise<string | null>;
  issueChallenge(
    userID: string,
  ): Promise<{ challenge: string; expires_at: string }>;
  consumeChallenge(userID: string, challenge: string): Promise<boolean>;
  registerKey(
    userID: string,
    keyID: string,
    publicKeySPKI: string,
    environment: AppAttestEnvironment,
  ): Promise<void>;
  getKey(userID: string, keyID: string): Promise<StoredAttestKey | null>;
  advanceCounter(keyID: string, counter: number): Promise<boolean>;
  recordAgeSignal(userID: string, age: MappedAge): Promise<RecordedAgeSignal>;
  deleteProfilePhotos(userID: string): Promise<void>;
  ageStatus(accessToken: string): Promise<unknown>;
}

export type AgeSignalFailureStage =
  | "configuration"
  | "authentication"
  | "challenge"
  | "attestation"
  | "assertion"
  | "record"
  | "photo_cleanup"
  | "status";

export type AgeSignalDependencies = {
  mode: AppAttestMode | null;
  backend?: AgeSignalBackend;
  rootCertificates?: x509.X509Certificate[];
  now?: () => Date;
  logRecorded?: (
    event: { changed: boolean; eligibleForAgeFeatures: boolean | null },
  ) => void;
  logFailure?: (event: { stage: AgeSignalFailureStage }) => void;
};

function json(body: unknown, status = 200): Response {
  return Response.json(body, {
    status,
    headers: {
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

async function readBoundedJSON(
  request: Request,
): Promise<{ ok: true; value: unknown } | { ok: false; response: Response }> {
  const contentType = request.headers.get("Content-Type")
    ?.split(";", 1)[0]
    .trim()
    .toLowerCase();
  if (contentType !== "application/json") {
    return {
      ok: false,
      response: json({ error: "unsupported_media_type" }, 415),
    };
  }
  const declared = request.headers.get("Content-Length");
  if (declared !== null) {
    const length = Number(declared);
    if (
      !Number.isSafeInteger(length) || length < 0 ||
      length > maxAgeSignalRequestBytes
    ) {
      return { ok: false, response: json({ error: "payload_too_large" }, 413) };
    }
  }

  const chunks: Uint8Array[] = [];
  let total = 0;
  if (request.body) {
    const reader = request.body.getReader();
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > maxAgeSignalRequestBytes) {
        await reader.cancel().catch(() => undefined);
        return {
          ok: false,
          response: json({ error: "payload_too_large" }, 413),
        };
      }
      chunks.push(value);
    }
  }

  try {
    const text = new TextDecoder("utf-8", { fatal: true }).decode(
      concat(...chunks),
    );
    return { ok: true, value: JSON.parse(text) };
  } catch {
    return { ok: false, response: json({ error: "invalid_request" }, 400) };
  }
}

function exactKeys(
  value: unknown,
  keys: string[],
): value is Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return false;
  }
  const present = Object.keys(value).sort();
  const expected = [...keys].sort();
  return present.length === expected.length &&
    present.every((key, index) => key === expected[index]) &&
    Object.values(value).every((entry) => typeof entry === "string");
}

function bearerToken(request: Request): string | null {
  const authorization = request.headers.get("Authorization");
  if (!authorization || authorization.length > 8_192) return null;
  return /^Bearer ([^\s]+)$/.exec(authorization)?.[1] ?? null;
}

function report(
  dependencies: AgeSignalDependencies,
  stage: AgeSignalFailureStage,
) {
  try {
    dependencies.logFailure?.({ stage });
  } catch {
    // Logging must never change the answer or carry the failure's detail.
  }
}

export async function handleAgeSignalRequest(
  request: Request,
  dependencies: AgeSignalDependencies,
): Promise<Response> {
  if (request.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const parsed = await readBoundedJSON(request);
  if (!parsed.ok) return parsed.response;
  const body = parsed.value as Record<string, unknown> | null;
  const step = body && typeof body === "object" ? body.step : undefined;

  const shapes: Record<string, string[]> = {
    challenge: ["step"],
    register: ["step", "challenge", "key_id", "attestation"],
    signal: ["step", "challenge", "key_id", "assertion", "signal_json"],
  };
  if (
    typeof step !== "string" || !shapes[step] || !exactKeys(body, shapes[step])
  ) {
    return json({ error: "invalid_request" }, 400);
  }

  const accessToken = bearerToken(request);
  if (!accessToken) return json({ error: "not_authenticated" }, 401);

  const backend = dependencies.backend;
  const mode = dependencies.mode;
  if (!backend || !mode) {
    report(dependencies, "configuration");
    return json({ error: "service_not_configured" }, 503);
  }

  let userID: string | null;
  try {
    userID = await backend.authenticatedUserID(accessToken);
  } catch {
    report(dependencies, "authentication");
    return json({ error: "service_unavailable" }, 503);
  }
  if (!userID) return json({ error: "not_authenticated" }, 401);

  if (step === "challenge") {
    try {
      return json(await backend.issueChallenge(userID));
    } catch (error) {
      if (error instanceof AgeSignalRateLimited) {
        return json({ error: "rate_limited" }, 429);
      }
      report(dependencies, "challenge");
      return json({ error: "service_unavailable" }, 503);
    }
  }

  const challenge = body!.challenge as string;
  const challengeBytes = decodeBase64URL(challenge);
  const keyID = body!.key_id as string;
  if (
    !challengeBytes || challengeBytes.byteLength !== 32 ||
    keyID.length < 1 || keyID.length > 200
  ) {
    return json({ error: "invalid_request" }, 400);
  }

  const insecure = mode === "insecure-local";
  if (insecure !== (keyID === insecureLocalKeyID)) {
    return json({ error: "app_attest_invalid" }, 401);
  }

  if (step === "register") {
    const attestationText = body!.attestation as string;
    if (!insecure) {
      const attestation = decodeBase64(attestationText);
      if (!attestation || attestation.byteLength === 0) {
        return json({ error: "app_attest_invalid" }, 401);
      }
      let verified: VerifiedAttestation;
      try {
        verified = await verifyAttestation({
          attestation,
          keyID,
          clientDataHash: await registrationClientDataHash(
            challengeBytes,
            userID,
          ),
          mode,
          rootCertificates: dependencies.rootCertificates ??
            rootCertificatesFrom(undefined),
          now: dependencies.now?.() ?? new Date(),
        });
      } catch {
        report(dependencies, "attestation");
        return json({ error: "app_attest_invalid" }, 401);
      }

      try {
        if (!(await backend.consumeChallenge(userID, challenge))) {
          return json({ error: "challenge_expired" }, 401);
        }
        await backend.registerKey(
          userID,
          keyID,
          verified.publicKeySPKI,
          verified.environment,
        );
      } catch {
        report(dependencies, "attestation");
        return json({ error: "service_unavailable" }, 503);
      }
    } else {
      if (attestationText !== "") {
        return json({ error: "app_attest_invalid" }, 401);
      }
      try {
        if (!(await backend.consumeChallenge(userID, challenge))) {
          return json({ error: "challenge_expired" }, 401);
        }
      } catch {
        report(dependencies, "challenge");
        return json({ error: "service_unavailable" }, 503);
      }
    }
    return json({ registered: true });
  }

  const signalJSON = body!.signal_json as string;
  if (new TextEncoder().encode(signalJSON).byteLength > maxSignalJSONBytes) {
    return json({ error: "invalid_request" }, 400);
  }
  const signal = parseAgeSignalJSON(signalJSON);
  if (!signal) return json({ error: "invalid_request" }, 400);

  const assertionText = body!.assertion as string;
  if (!insecure) {
    const assertion = decodeBase64(assertionText);
    if (!assertion || assertion.byteLength === 0) {
      return json({ error: "app_attest_invalid" }, 401);
    }

    let stored: StoredAttestKey | null;
    try {
      stored = await backend.getKey(userID, keyID);
    } catch {
      report(dependencies, "assertion");
      return json({ error: "service_unavailable" }, 503);
    }
    if (!stored || stored.environment !== mode) {
      return json({ error: "app_attest_key_unknown" }, 401);
    }

    let counter: number;
    try {
      ({ counter } = await verifyAssertion({
        assertion,
        publicKeySPKI: stored.public_key_spki,
        storedCounter: stored.counter,
        clientDataHash: await assertionClientDataHash(
          challengeBytes,
          signalJSON,
        ),
      }));
    } catch {
      report(dependencies, "assertion");
      return json({ error: "app_attest_invalid" }, 401);
    }

    try {
      if (!(await backend.advanceCounter(keyID, counter))) {
        return json({ error: "app_attest_invalid" }, 401);
      }
    } catch {
      report(dependencies, "assertion");
      return json({ error: "service_unavailable" }, 503);
    }
  } else if (assertionText !== "") {
    return json({ error: "app_attest_invalid" }, 401);
  }

  try {
    if (!(await backend.consumeChallenge(userID, challenge))) {
      return json({ error: "challenge_expired" }, 401);
    }
  } catch {
    report(dependencies, "challenge");
    return json({ error: "service_unavailable" }, 503);
  }

  const age = mapAgeRange(signal);
  let recorded: RecordedAgeSignal;
  try {
    recorded = await backend.recordAgeSignal(userID, age);
  } catch (error) {
    if (error instanceof AgeSignalRejected) {
      try {
        return json({
          error: "age_signal_rejected",
          age_status: await backend.ageStatus(accessToken),
        }, 409);
      } catch {
        report(dependencies, "status");
        return json({ error: "age_signal_rejected" }, 409);
      }
    }
    report(dependencies, "record");
    return json({ error: "service_unavailable" }, 503);
  }

  // A minor's photo is removed on every signal that finds them one, so a
  // cleanup that failed once is retried rather than forgotten.
  if (recorded.photo_cleanup_required || recorded.status !== "adult") {
    try {
      await backend.deleteProfilePhotos(userID);
    } catch {
      report(dependencies, "photo_cleanup");
    }
  }

  try {
    dependencies.logRecorded?.({
      changed: recorded.changed,
      eligibleForAgeFeatures: signal.eligible_for_age_features,
    });
  } catch {
    // Logging must never change the answer.
  }

  try {
    return json({ age_status: await backend.ageStatus(accessToken) });
  } catch {
    report(dependencies, "status");
    return json({ error: "service_unavailable" }, 503);
  }
}
