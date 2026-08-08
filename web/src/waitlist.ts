export const waitlistConsentVersion = "2026-07-29";

const maxRequestBytes = 4_096;
const upstreamTimeoutMilliseconds = 5_000;
const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/u;
const sourcePattern = /^[a-z0-9_-]{1,40}$/u;
const localePattern = /^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$/u;
const unsubscribeTokenPattern = /^[0-9a-f]{64}$/u;
const waitlistHealthSchemaVersion = "2026-08-02";

export interface WaitlistEnvironment {
  supabaseUrl?: string;
  publishableKey?: string;
  secretKey?: string;
  hashSalt?: string;
}

export interface WaitlistRequestContext {
  clientIP?: string;
  fetcher?: typeof fetch;
}

export interface WaitlistDependencyContext {
  fetcher?: typeof fetch;
}

export interface WaitlistConfigurationStatus {
  inviteLookup: boolean;
  waitlist: boolean;
}

interface WaitlistPayload {
  email?: unknown;
  firstName?: unknown;
  consent?: unknown;
  consentVersion?: unknown;
  source?: unknown;
  locale?: unknown;
  website?: unknown;
}

interface WaitlistUnsubscribePayload {
  token?: unknown;
}

interface WaitlistRPCResult {
  accepted?: boolean;
  reason?: string;
}

interface InviteHealthResult {
  valid?: boolean;
}

interface WaitlistHealthResult {
  ready?: boolean;
  schema_version?: string;
}

function requestGuard(request: Request): Response | null {
  if (request.method !== "POST") {
    return jsonResponse(
      { accepted: false, error: "method_not_allowed" },
      405,
      { Allow: "POST" },
    );
  }

  const requestURL = new URL(request.url);
  const origin = request.headers.get("Origin");
  const fetchSite = request.headers.get("Sec-Fetch-Site");
  if (
    (origin && origin !== requestURL.origin) ||
    fetchSite === "cross-site"
  ) {
    return jsonResponse({ accepted: false, error: "origin_not_allowed" }, 403);
  }

  const contentType = request.headers.get("Content-Type")?.split(";", 1)[0]
    ?.trim().toLowerCase();
  if (contentType !== "application/json") {
    return jsonResponse(
      { accepted: false, error: "content_type_required" },
      415,
    );
  }

  const declaredLength = Number(request.headers.get("Content-Length") ?? "0");
  if (Number.isFinite(declaredLength) && declaredLength > maxRequestBytes) {
    return jsonResponse({ accepted: false, error: "request_too_large" }, 413);
  }

  return null;
}

async function requestPayload(
  request: Request,
): Promise<Record<string, unknown> | Response> {
  try {
    const rawBody = await request.text();
    if (new TextEncoder().encode(rawBody).byteLength > maxRequestBytes) {
      return jsonResponse({ accepted: false, error: "request_too_large" }, 413);
    }

    const parsed: unknown = JSON.parse(rawBody);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return jsonResponse({ accepted: false, error: "invalid_request" }, 400);
    }
    return parsed as Record<string, unknown>;
  } catch {
    return jsonResponse({ accepted: false, error: "invalid_json" }, 400);
  }
}

function jsonResponse(
  body: Record<string, unknown>,
  status: number,
  headers: Record<string, string> = {},
): Response {
  return Response.json(body, {
    status,
    headers: {
      "Cache-Control": "no-store",
      ...headers,
    },
  });
}

function normalizedText(value: unknown, maximumLength: number): string {
  if (typeof value !== "string") return "";
  return value.trim().replace(/\s+/gu, " ").slice(0, maximumLength);
}

function normalizedLocale(
  value: unknown,
  acceptLanguage: string | null,
): string {
  const submitted = normalizedText(value, 20);
  if (localePattern.test(submitted)) return submitted;

  const preferred = acceptLanguage
    ?.split(",", 1)[0]
    ?.split(";", 1)[0]
    ?.trim()
    .slice(0, 20) ?? "";
  return localePattern.test(preferred) ? preferred : "pt-BR";
}

export function resolveSupabaseURL(rawValue: string | undefined): URL | null {
  if (!rawValue) return null;

  try {
    const url = new URL(rawValue);
    const isSecure = url.protocol === "https:";
    const isLocal = url.protocol === "http:" &&
      ["127.0.0.1", "localhost", "[::1]"].includes(url.hostname);
    const isRoot = (url.pathname === "/" || url.pathname === "") &&
      !url.search &&
      !url.hash &&
      !url.username &&
      !url.password;
    return (isSecure || isLocal) && isRoot ? url : null;
  } catch {
    return null;
  }
}

function decodedJWTRole(value: string): string | undefined {
  const segments = value.split(".");
  if (segments.length !== 3 || segments.some((segment) => !segment)) {
    return undefined;
  }

  try {
    const normalized = segments[1]
      .replaceAll("-", "+")
      .replaceAll("_", "/")
      .padEnd(Math.ceil(segments[1].length / 4) * 4, "=");
    const payload: unknown = JSON.parse(atob(normalized));
    if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
      return undefined;
    }
    const role = (payload as Record<string, unknown>).role;
    return typeof role === "string" ? role : undefined;
  } catch {
    return undefined;
  }
}

function isPublishableKey(rawValue: string | undefined): boolean {
  const value = rawValue?.trim() ?? "";
  if (!value || /\s/u.test(value) || value.includes("$(")) return false;
  if (value.startsWith("sb_publishable_")) {
    return value.slice("sb_publishable_".length).length >= 16;
  }
  return decodedJWTRole(value) === "anon";
}

function isSecretKey(rawValue: string | undefined): boolean {
  const value = rawValue?.trim() ?? "";
  return value.startsWith("sb_secret_") &&
    value.slice("sb_secret_".length).length >= 16 &&
    !/\s/u.test(value) &&
    !value.includes("$(");
}

export function waitlistConfigurationStatus(
  environment: WaitlistEnvironment,
): WaitlistConfigurationStatus {
  const backendURL = resolveSupabaseURL(environment.supabaseUrl);
  const inviteLookup = Boolean(
    backendURL &&
      isPublishableKey(environment.publishableKey),
  );
  const hashSalt = environment.hashSalt?.trim() ?? "";

  return {
    inviteLookup,
    waitlist: Boolean(
      backendURL &&
        isSecretKey(environment.secretKey) &&
        hashSalt.length >= 32,
    ),
  };
}

async function requestFingerprint(
  hashSalt: string,
  clientIP: string,
): Promise<string> {
  const input = new TextEncoder().encode(`${hashSalt}\u0000${clientIP}`);
  const digest = await crypto.subtle.digest("SHA-256", input);
  return Array.from(
    new Uint8Array(digest),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
}

async function safeJSON<Result extends object>(
  response: Response,
): Promise<Result | null> {
  try {
    const declaredLength = Number(
      response.headers.get("Content-Length") ?? "0",
    );
    if (Number.isFinite(declaredLength) && declaredLength > maxRequestBytes) {
      return null;
    }
    const rawBody = await response.text();
    if (new TextEncoder().encode(rawBody).byteLength > maxRequestBytes) {
      return null;
    }
    const payload: unknown = JSON.parse(rawBody);
    if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
      return null;
    }
    return payload as Result;
  } catch {
    return null;
  }
}

async function healthProbe<Result extends object>(
  url: URL,
  key: string,
  body: Record<string, unknown>,
  validator: (result: Result) => boolean,
  fetcher: typeof fetch,
): Promise<boolean> {
  try {
    const response = await fetcher(url, {
      method: "POST",
      signal: AbortSignal.timeout(upstreamTimeoutMilliseconds),
      headers: {
        apikey: key,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    });
    if (!response.ok) return false;
    const result = await safeJSON<Result>(response);
    return result !== null && validator(result);
  } catch {
    return false;
  }
}

export async function checkWaitlistDependencies(
  environment: WaitlistEnvironment,
  context: WaitlistDependencyContext = {},
): Promise<WaitlistConfigurationStatus> {
  const configuration = waitlistConfigurationStatus(environment);
  const backendURL = resolveSupabaseURL(environment.supabaseUrl);
  if (!backendURL) return { inviteLookup: false, waitlist: false };

  const fetcher = context.fetcher ?? fetch;
  const publishableKey = environment.publishableKey?.trim() ?? "";
  const secretKey = environment.secretKey?.trim() ?? "";
  const inviteProbe = configuration.inviteLookup
    ? healthProbe<InviteHealthResult>(
      new URL("/rest/v1/rpc/get_family_invite_preview", backendURL),
      publishableKey,
      { invite_code: "healthcheck-missing-invite" },
      (result) => result.valid === false,
      fetcher,
    )
    : Promise.resolve(false);
  const waitlistProbe = configuration.waitlist
    ? healthProbe<WaitlistHealthResult>(
      new URL("/rest/v1/rpc/waitlist_healthcheck", backendURL),
      secretKey,
      {},
      (result) =>
        result.ready === true &&
        result.schema_version === waitlistHealthSchemaVersion,
      fetcher,
    )
    : Promise.resolve(false);

  const [inviteLookup, waitlist] = await Promise.all([
    inviteProbe,
    waitlistProbe,
  ]);
  return { inviteLookup, waitlist };
}

export async function handleWaitlistSignup(
  request: Request,
  environment: WaitlistEnvironment,
  context: WaitlistRequestContext = {},
): Promise<Response> {
  const guardResponse = requestGuard(request);
  if (guardResponse) return guardResponse;

  const parsedPayload = await requestPayload(request);
  if (parsedPayload instanceof Response) return parsedPayload;
  const payload = parsedPayload as WaitlistPayload;

  // A filled honeypot receives the same generic success as a real submission.
  if (normalizedText(payload.website, 200)) {
    return jsonResponse({ accepted: true }, 202);
  }

  const email = normalizedText(payload.email, 254).toLowerCase();
  const firstName = normalizedText(payload.firstName, 80);
  const consentVersion = normalizedText(payload.consentVersion, 40);
  const sourceCandidate = normalizedText(payload.source, 40).toLowerCase();
  const source = sourcePattern.test(sourceCandidate)
    ? sourceCandidate
    : "landing";
  const locale = normalizedLocale(
    payload.locale,
    request.headers.get("Accept-Language"),
  );

  if (!emailPattern.test(email) || email.length > 254) {
    return jsonResponse({ accepted: false, error: "invalid_email" }, 400);
  }

  if (payload.consent !== true || consentVersion !== waitlistConsentVersion) {
    return jsonResponse({ accepted: false, error: "consent_required" }, 400);
  }

  const backendURL = resolveSupabaseURL(environment.supabaseUrl);
  const secretKey = environment.secretKey?.trim();
  const hashSalt = environment.hashSalt?.trim();
  if (
    !waitlistConfigurationStatus(environment).waitlist ||
    !backendURL ||
    !secretKey ||
    !hashSalt
  ) {
    return jsonResponse(
      { accepted: false, error: "waitlist_unavailable" },
      503,
      { "Retry-After": "300" },
    );
  }

  const fingerprint = await requestFingerprint(
    hashSalt,
    context.clientIP?.trim() || "ip-unavailable",
  );
  const rpcURL = new URL("/rest/v1/rpc/register_waitlist_signup", backendURL);
  const fetcher = context.fetcher ?? fetch;

  let upstream: Response;
  try {
    upstream = await fetcher(rpcURL, {
      method: "POST",
      signal: AbortSignal.timeout(upstreamTimeoutMilliseconds),
      headers: {
        apikey: secretKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        p_email: email,
        p_first_name: firstName || null,
        p_consent: true,
        p_consent_version: consentVersion,
        p_source: source,
        p_locale: locale,
        p_request_fingerprint: fingerprint,
      }),
    });
  } catch {
    return jsonResponse(
      { accepted: false, error: "waitlist_unavailable" },
      503,
      { "Retry-After": "60" },
    );
  }

  const result = await safeJSON<WaitlistRPCResult>(upstream);
  if (!upstream.ok) {
    return jsonResponse(
      { accepted: false, error: "waitlist_upstream_failed" },
      502,
      { "Retry-After": "60" },
    );
  }

  if (result?.accepted === false && result.reason === "rate_limited") {
    return jsonResponse(
      { accepted: false, error: "rate_limited" },
      429,
      { "Retry-After": "3600" },
    );
  }

  if (result?.accepted !== true) {
    return jsonResponse(
      { accepted: false, error: "waitlist_upstream_failed" },
      502,
      { "Retry-After": "60" },
    );
  }

  // The public response never reveals whether the email was new or already registered.
  return jsonResponse({ accepted: true }, 202);
}

export async function handleWaitlistUnsubscribe(
  request: Request,
  environment: WaitlistEnvironment,
  context: Pick<WaitlistRequestContext, "fetcher"> = {},
): Promise<Response> {
  const guardResponse = requestGuard(request);
  if (guardResponse) return guardResponse;

  const parsedPayload = await requestPayload(request);
  if (parsedPayload instanceof Response) return parsedPayload;
  const payload = parsedPayload as WaitlistUnsubscribePayload;
  const token = normalizedText(payload.token, 64).toLowerCase();

  // Malformed capabilities get the same response as unknown or already-used ones.
  if (!unsubscribeTokenPattern.test(token)) {
    return jsonResponse({ accepted: true }, 202);
  }

  const backendURL = resolveSupabaseURL(environment.supabaseUrl);
  const secretKey = environment.secretKey?.trim();
  if (
    !waitlistConfigurationStatus(environment).waitlist ||
    !backendURL ||
    !secretKey
  ) {
    return jsonResponse(
      { accepted: false, error: "waitlist_unavailable" },
      503,
      { "Retry-After": "300" },
    );
  }

  const rpcURL = new URL(
    "/rest/v1/rpc/unsubscribe_waitlist_signup",
    backendURL,
  );
  const fetcher = context.fetcher ?? fetch;

  let upstream: Response;
  try {
    upstream = await fetcher(rpcURL, {
      method: "POST",
      signal: AbortSignal.timeout(upstreamTimeoutMilliseconds),
      headers: {
        apikey: secretKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ p_token: token }),
    });
  } catch {
    return jsonResponse(
      { accepted: false, error: "waitlist_unavailable" },
      503,
      { "Retry-After": "60" },
    );
  }

  const result = await safeJSON<WaitlistRPCResult>(upstream);
  if (!upstream.ok || result?.accepted !== true) {
    return jsonResponse(
      { accepted: false, error: "waitlist_upstream_failed" },
      502,
      { "Retry-After": "60" },
    );
  }

  return jsonResponse({ accepted: true }, 202);
}
