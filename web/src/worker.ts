import {
  checkWaitlistDependencies,
  handleWaitlistSignup,
  handleWaitlistUnsubscribe,
  resolveSupabaseURL,
  type WaitlistEnvironment,
} from "./waitlist.ts";

interface Env {
  ASSETS: Fetcher;
  SUPABASE_URL?: string;
  SUPABASE_PUBLISHABLE_KEY?: string;
  SUPABASE_SECRET_KEY?: string;
  NINA_SUPABASE_URL?: string;
  NINA_SUPABASE_PUBLISHABLE_KEY?: string;
  NINA_SUPABASE_SECRET_KEY?: string;
  WAITLIST_HASH_SALT?: string;
  NINA_WAITLIST_HASH_SALT?: string;
}

interface InvitePreview {
  valid: boolean;
  family_name?: string;
  expires_at?: string;
  uses_remaining?: number;
}

const securityHeaders = {
  "Content-Security-Policy":
    "default-src 'self'; base-uri 'self'; object-src 'none'; frame-ancestors 'none'; form-action 'self'; img-src 'self' data:; script-src 'self'; style-src 'self'; connect-src 'self'; manifest-src 'self'; media-src 'self'",
  "Cross-Origin-Opener-Policy": "same-origin",
  "Cross-Origin-Resource-Policy": "same-origin",
  "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
  "Referrer-Policy": "strict-origin-when-cross-origin",
  "Strict-Transport-Security": "max-age=31536000",
  "X-Frame-Options": "DENY",
  "X-Content-Type-Options": "nosniff",
  "X-XSS-Protection": "0",
};
const upstreamTimeoutMilliseconds = 5_000;

function jsonResponse(
  body: unknown,
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

function waitlistEnvironment(env: Env): WaitlistEnvironment {
  return {
    supabaseUrl: env.SUPABASE_URL ?? env.NINA_SUPABASE_URL,
    publishableKey: env.SUPABASE_PUBLISHABLE_KEY ??
      env.NINA_SUPABASE_PUBLISHABLE_KEY,
    secretKey: env.SUPABASE_SECRET_KEY ?? env.NINA_SUPABASE_SECRET_KEY,
    hashSalt: env.WAITLIST_HASH_SALT ?? env.NINA_WAITLIST_HASH_SALT,
  };
}

async function healthResponse(env: Env): Promise<Response> {
  const { inviteLookup, waitlist } = await checkWaitlistDependencies(
    waitlistEnvironment(env),
  );
  const ready = inviteLookup && waitlist;

  return jsonResponse(
    {
      status: ready ? "ok" : "degraded",
      service: "nina-web",
      checks: {
        inviteLookup,
        waitlist,
      },
    },
    ready ? 200 : 503,
    ready ? {} : { "Retry-After": "300" },
  );
}

async function getInvitePreview(code: string, env: Env): Promise<Response> {
  const normalizedCode = code.toLowerCase().replace(/[^a-z0-9-]/g, "");

  if (normalizedCode.length < 12 || normalizedCode.length > 96) {
    return jsonResponse({ valid: false, error: "invalid_invite" }, 400);
  }

  const supabaseUrl = resolveSupabaseURL(
    env.SUPABASE_URL ?? env.NINA_SUPABASE_URL,
  );
  const publishableKey = (
    env.SUPABASE_PUBLISHABLE_KEY ??
      env.NINA_SUPABASE_PUBLISHABLE_KEY
  )?.trim();

  if (!supabaseUrl || !publishableKey) {
    return jsonResponse(
      { valid: false, error: "invite_lookup_unavailable" },
      503,
    );
  }

  const rpcURL = new URL("/rest/v1/rpc/get_family_invite_preview", supabaseUrl);
  let response: Response;
  try {
    response = await fetch(rpcURL, {
      method: "POST",
      signal: AbortSignal.timeout(upstreamTimeoutMilliseconds),
      headers: {
        apikey: publishableKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ invite_code: normalizedCode }),
    });
  } catch {
    return jsonResponse(
      { valid: false, error: "invite_lookup_unavailable" },
      503,
      { "Retry-After": "60" },
    );
  }

  if (!response.ok) {
    return jsonResponse({ valid: false, error: "invite_lookup_failed" }, 502);
  }

  let preview: InvitePreview;
  try {
    preview = (await response.json()) as InvitePreview;
  } catch {
    return jsonResponse({ valid: false, error: "invite_lookup_failed" }, 502);
  }

  if (!preview.valid) {
    return jsonResponse({ valid: false, error: "invite_not_found" }, 404);
  }

  return jsonResponse(
    {
      valid: true,
      verified: true,
      familyName: preview.family_name ?? "Uma casa na Nina",
      expiresAt: preview.expires_at,
      usesRemaining: preview.uses_remaining,
    },
    200,
  );
}

async function serveInvitePage(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  url.pathname = "/join/";

  const response = await env.ASSETS.fetch(new Request(url, request));
  return withSecurityHeaders(response);
}

function withSecurityHeaders(response: Response): Response {
  const contentType = response.headers.get("Content-Type") ?? "";
  const normalizedContentType = contentType.toLowerCase();
  if (
    !normalizedContentType.includes("text/html") &&
    !normalizedContentType.includes("application/json")
  ) {
    return response;
  }

  const headers = new Headers(response.headers);

  for (const [name, value] of Object.entries(securityHeaders)) {
    headers.set(name, value);
  }

  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

async function observedAPIResponse(
  operation: string,
  responseProvider: () => Promise<Response> | Response,
): Promise<Response> {
  const requestID = crypto.randomUUID();
  const startedAt = performance.now();
  let response: Response;
  let failureType: string | undefined;

  try {
    response = await responseProvider();
  } catch (error) {
    failureType = error instanceof Error ? error.name : "UnknownError";
    response = jsonResponse({ error: "internal_error" }, 500);
  }

  const securedResponse = withSecurityHeaders(response);
  const headers = new Headers(securedResponse.headers);
  headers.set("X-Request-ID", requestID);

  console.info(JSON.stringify({
    event: "nina_web_api",
    operation,
    request_id: requestID,
    status: securedResponse.status,
    duration_ms: Math.round(performance.now() - startedAt),
    ...(failureType ? { failure_type: failureType } : {}),
  }));

  return new Response(securedResponse.body, {
    status: securedResponse.status,
    statusText: securedResponse.statusText,
    headers,
  });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const inviteApiMatch = url.pathname.match(/^\/api\/invite\/([^/]+)\/?$/);

    if (request.method === "GET" && inviteApiMatch) {
      return observedAPIResponse(
        "invite_preview",
        () => getInvitePreview(inviteApiMatch[1], env),
      );
    }

    if (url.pathname === "/api/waitlist") {
      return observedAPIResponse(
        "waitlist_signup",
        () =>
          handleWaitlistSignup(
            request,
            waitlistEnvironment(env),
            { clientIP: request.headers.get("CF-Connecting-IP") ?? undefined },
          ),
      );
    }

    if (url.pathname === "/api/waitlist/unsubscribe") {
      return observedAPIResponse(
        "waitlist_unsubscribe",
        () =>
          handleWaitlistUnsubscribe(
            request,
            waitlistEnvironment(env),
          ),
      );
    }

    if (url.pathname === "/api/health") {
      return observedAPIResponse(
        "health",
        () =>
          request.method === "GET" ? healthResponse(env) : jsonResponse(
            { error: "method_not_allowed" },
            405,
            { Allow: "GET" },
          ),
      );
    }

    if (request.method === "GET" && url.pathname.startsWith("/invite/")) {
      return serveInvitePage(request, env);
    }

    return withSecurityHeaders(await env.ASSETS.fetch(request));
  },
} satisfies ExportedHandler<Env>;
