import { assert, assertEquals, assertMatch } from "@std/assert";
import {
  checkWaitlistDependencies,
  handleWaitlistSignup,
  handleWaitlistUnsubscribe,
  resolveSupabaseURL,
  waitlistConfigurationStatus,
  waitlistConsentVersion,
} from "../src/waitlist.ts";

const environment = {
  supabaseUrl: "https://project.supabase.co",
  publishableKey: "sb_publishable_A1b2C3d4E5f6G7h8I9j0",
  secretKey: `sb_${"secret"}_a-production-server-key-1234567890`,
  hashSalt: "a-production-secret-with-at-least-32-characters",
};

function signupRequest(
  payload: Record<string, unknown>,
  headers: Record<string, string> = {},
): Request {
  return new Request("https://ninai.app/api/waitlist", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Origin: "https://ninai.app",
      ...headers,
    },
    body: JSON.stringify(payload),
  });
}

function validPayload(
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    email: " Pessoa@Example.com ",
    firstName: " Ana   Maria ",
    consent: true,
    consentVersion: waitlistConsentVersion,
    source: "hero",
    locale: "pt-BR",
    website: "",
    ...overrides,
  };
}

function unsubscribeRequest(
  token: unknown,
  headers: Record<string, string> = {},
): Request {
  return new Request("https://ninai.app/api/waitlist/unsubscribe", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Origin: "https://ninai.app",
      ...headers,
    },
    body: JSON.stringify({ token }),
  });
}

Deno.test("valid signup is normalized and returns a generic accepted response", async () => {
  let rpcBody: Record<string, unknown> | undefined;
  const fetcher = ((input: RequestInfo | URL, init?: RequestInit) => {
    assertEquals(
      String(input),
      "https://project.supabase.co/rest/v1/rpc/register_waitlist_signup",
    );
    assertEquals(init?.method, "POST");
    const headers = new Headers(init?.headers);
    assertEquals(headers.get("apikey"), environment.secretKey);
    assertEquals(headers.get("Authorization"), null);
    rpcBody = JSON.parse(String(init?.body)) as Record<string, unknown>;
    return Promise.resolve(Response.json({ accepted: true }));
  }) as typeof fetch;

  const response = await handleWaitlistSignup(
    signupRequest(validPayload()),
    environment,
    { clientIP: "203.0.113.10", fetcher },
  );

  assertEquals(response.status, 202);
  assertEquals(await response.json(), { accepted: true });
  assertEquals(rpcBody?.p_email, "pessoa@example.com");
  assertEquals(rpcBody?.p_first_name, "Ana Maria");
  assertEquals(rpcBody?.p_source, "hero");
  assertMatch(String(rpcBody?.p_request_fingerprint), /^[0-9a-f]{64}$/u);
  assert(!JSON.stringify(rpcBody).includes("203.0.113.10"));
});

Deno.test("weighted browser locale is normalized before persistence", async () => {
  let rpcBody: Record<string, unknown> | undefined;
  const fetcher = ((_input: RequestInfo | URL, init?: RequestInit) => {
    rpcBody = JSON.parse(String(init?.body)) as Record<string, unknown>;
    return Promise.resolve(Response.json({ accepted: true }));
  }) as typeof fetch;

  const response = await handleWaitlistSignup(
    signupRequest(
      validPayload({ locale: "invalid locale" }),
      { "Accept-Language": "en-US;q=0.9,pt-BR;q=0.8" },
    ),
    environment,
    { clientIP: "203.0.113.15", fetcher },
  );

  assertEquals(response.status, 202);
  assertEquals(rpcBody?.p_locale, "en-US");
});

Deno.test("readiness uses the same strict configuration checks as signup", () => {
  assertEquals(waitlistConfigurationStatus(environment), {
    inviteLookup: true,
    waitlist: true,
  });
  assertEquals(
    waitlistConfigurationStatus({
      supabaseUrl: "http://project.supabase.co",
      publishableKey: "   ",
      secretKey: "sb_secret_too-short",
      hashSalt: "short",
    }),
    {
      inviteLookup: false,
      waitlist: false,
    },
  );
});

Deno.test("Supabase URLs are limited to root HTTPS or loopback development origins", () => {
  assertEquals(
    resolveSupabaseURL("https://project.supabase.co")?.origin,
    "https://project.supabase.co",
  );
  assertEquals(
    resolveSupabaseURL("http://127.0.0.1:54321")?.origin,
    "http://127.0.0.1:54321",
  );
  assertEquals(resolveSupabaseURL("http://project.supabase.co"), null);
  assertEquals(resolveSupabaseURL("https://user@project.supabase.co"), null);
  assertEquals(resolveSupabaseURL("https://project.supabase.co/rest/v1"), null);
  assertEquals(resolveSupabaseURL("https://project.supabase.co?debug=1"), null);
});

Deno.test("live readiness probes both public and service database contracts", async () => {
  const requestedPaths = new Set<string>();
  const fetcher = ((input: RequestInfo | URL, init?: RequestInit) => {
    const url = new URL(String(input));
    requestedPaths.add(url.pathname);
    const headers = new Headers(init?.headers);
    assertEquals(init?.method, "POST");
    assertEquals(headers.get("Authorization"), null);

    if (url.pathname.endsWith("/get_family_invite_preview")) {
      assertEquals(headers.get("apikey"), environment.publishableKey);
      assertEquals(JSON.parse(String(init?.body)), {
        invite_code: "healthcheck-missing-invite",
      });
      return Promise.resolve(Response.json({ valid: false }));
    }

    assertEquals(url.pathname, "/rest/v1/rpc/waitlist_healthcheck");
    assertEquals(headers.get("apikey"), environment.secretKey);
    assertEquals(JSON.parse(String(init?.body)), {});
    return Promise.resolve(Response.json({
      ready: true,
      schema_version: "2026-08-02",
    }));
  }) as typeof fetch;

  assertEquals(
    await checkWaitlistDependencies(environment, { fetcher }),
    { inviteLookup: true, waitlist: true },
  );
  assertEquals(
    requestedPaths,
    new Set([
      "/rest/v1/rpc/get_family_invite_preview",
      "/rest/v1/rpc/waitlist_healthcheck",
    ]),
  );
});

Deno.test("live readiness degrades on stale or malformed contracts", async () => {
  const fetcher = ((input: RequestInfo | URL) => {
    const path = new URL(String(input)).pathname;
    if (path.endsWith("/get_family_invite_preview")) {
      return Promise.resolve(Response.json({ valid: "false" }));
    }
    return Promise.resolve(Response.json({
      ready: true,
      schema_version: "2026-07-29",
    }));
  }) as typeof fetch;

  assertEquals(
    await checkWaitlistDependencies(environment, { fetcher }),
    { inviteLookup: false, waitlist: false },
  );
});

Deno.test("live readiness rejects oversized upstream responses", async () => {
  const fetcher = (() =>
    Promise.resolve(
      new Response("{}", {
        headers: { "Content-Length": "5000" },
      }),
    )) as typeof fetch;

  assertEquals(
    await checkWaitlistDependencies(environment, { fetcher }),
    { inviteLookup: false, waitlist: false },
  );
});

Deno.test("live readiness fails closed on network errors without throwing", async () => {
  const fetcher =
    (() =>
      Promise.reject(new TypeError("network unavailable"))) as typeof fetch;

  assertEquals(
    await checkWaitlistDependencies(environment, { fetcher }),
    { inviteLookup: false, waitlist: false },
  );
});

Deno.test("opaque Supabase keys are never sent as bearer JWTs by the worker", async () => {
  const workerSource = await Deno.readTextFile(
    new URL("../src/worker.ts", import.meta.url),
  );

  assert(workerSource.includes("apikey: publishableKey"));
  assert(workerSource.includes("await checkWaitlistDependencies"));
  assert(!workerSource.includes("Authorization: `Bearer ${publishableKey}`"));
  assert(!workerSource.includes("Authorization: `Bearer ${secretKey}`"));
});

Deno.test("response does not reveal whether an email already existed", async () => {
  const fetcher = (() =>
    Promise.resolve(Response.json({
      accepted: true,
      already_registered: true,
    }))) as typeof fetch;

  const response = await handleWaitlistSignup(
    signupRequest(validPayload()),
    environment,
    { clientIP: "203.0.113.11", fetcher },
  );

  assertEquals(await response.json(), { accepted: true });
});

Deno.test("cross-site submissions are rejected before reaching Supabase", async () => {
  let didFetch = false;
  const fetcher = (() => {
    didFetch = true;
    return Promise.resolve(Response.json({ accepted: true }));
  }) as typeof fetch;

  const response = await handleWaitlistSignup(
    signupRequest(validPayload(), { Origin: "https://example.com" }),
    environment,
    { clientIP: "203.0.113.12", fetcher },
  );

  assertEquals(response.status, 403);
  assertEquals(didFetch, false);
});

Deno.test("email and explicit current consent are validated", async () => {
  const invalidEmail = await handleWaitlistSignup(
    signupRequest(validPayload({ email: "invalid" })),
    environment,
  );
  const missingConsent = await handleWaitlistSignup(
    signupRequest(validPayload({ consent: false })),
    environment,
  );
  const staleConsent = await handleWaitlistSignup(
    signupRequest(validPayload({ consentVersion: "old-version" })),
    environment,
  );

  assertEquals(invalidEmail.status, 400);
  assertEquals(missingConsent.status, 400);
  assertEquals(staleConsent.status, 400);
});

Deno.test("honeypot submissions receive a generic success without persistence", async () => {
  let didFetch = false;
  const fetcher = (() => {
    didFetch = true;
    return Promise.resolve(Response.json({ accepted: true }));
  }) as typeof fetch;

  const response = await handleWaitlistSignup(
    signupRequest(validPayload({ website: "spam.example" })),
    {},
    { fetcher },
  );

  assertEquals(response.status, 202);
  assertEquals(didFetch, false);
});

Deno.test("missing production configuration fails closed", async () => {
  const response = await handleWaitlistSignup(
    signupRequest(validPayload()),
    {},
  );

  assertEquals(response.status, 503);
  assertEquals(response.headers.get("Retry-After"), "300");
});

Deno.test("database rate limits are mapped to HTTP 429 and committed", async () => {
  const fetcher = (() =>
    Promise.resolve(Response.json({
      accepted: false,
      reason: "rate_limited",
    }))) as typeof fetch;

  const response = await handleWaitlistSignup(
    signupRequest(validPayload()),
    environment,
    { clientIP: "203.0.113.13", fetcher },
  );

  assertEquals(response.status, 429);
  assertEquals(response.headers.get("Retry-After"), "3600");
});

Deno.test("upstream network failures return a retryable unavailable response", async () => {
  const fetcher =
    (() =>
      Promise.reject(new TypeError("network unavailable"))) as typeof fetch;

  const response = await handleWaitlistSignup(
    signupRequest(validPayload()),
    environment,
    { clientIP: "203.0.113.14", fetcher },
  );

  assertEquals(response.status, 503);
  assertEquals(response.headers.get("Retry-After"), "60");
});

Deno.test("valid unsubscribe capabilities use the service-only RPC", async () => {
  const token = "a".repeat(64);
  let rpcBody: Record<string, unknown> | undefined;
  const fetcher = ((input: RequestInfo | URL, init?: RequestInit) => {
    assertEquals(
      String(input),
      "https://project.supabase.co/rest/v1/rpc/unsubscribe_waitlist_signup",
    );
    assertEquals(init?.method, "POST");
    const headers = new Headers(init?.headers);
    assertEquals(headers.get("apikey"), environment.secretKey);
    assertEquals(headers.get("Authorization"), null);
    rpcBody = JSON.parse(String(init?.body)) as Record<string, unknown>;
    return Promise.resolve(Response.json({ accepted: true }));
  }) as typeof fetch;

  const response = await handleWaitlistUnsubscribe(
    unsubscribeRequest(token),
    environment,
    { fetcher },
  );

  assertEquals(response.status, 202);
  assertEquals(await response.json(), { accepted: true });
  assertEquals(rpcBody, { p_token: token });
});

Deno.test("malformed unsubscribe capabilities receive an opaque success locally", async () => {
  let didFetch = false;
  const fetcher = (() => {
    didFetch = true;
    return Promise.resolve(Response.json({ accepted: true }));
  }) as typeof fetch;

  const response = await handleWaitlistUnsubscribe(
    unsubscribeRequest("not-a-token"),
    {},
    { fetcher },
  );

  assertEquals(response.status, 202);
  assertEquals(await response.json(), { accepted: true });
  assertEquals(didFetch, false);
});

Deno.test("unsubscribe responses cannot reveal capability state", async () => {
  const fetcher = (() =>
    Promise.resolve(Response.json({
      accepted: true,
      matched: false,
      already_unsubscribed: true,
    }))) as typeof fetch;

  const response = await handleWaitlistUnsubscribe(
    unsubscribeRequest("b".repeat(64)),
    environment,
    { fetcher },
  );

  assertEquals(await response.json(), { accepted: true });
});

Deno.test("cross-site unsubscribe attempts are rejected before persistence", async () => {
  let didFetch = false;
  const fetcher = (() => {
    didFetch = true;
    return Promise.resolve(Response.json({ accepted: true }));
  }) as typeof fetch;

  const response = await handleWaitlistUnsubscribe(
    unsubscribeRequest("c".repeat(64), {
      Origin: "https://example.com",
      "Sec-Fetch-Site": "cross-site",
    }),
    environment,
    { fetcher },
  );

  assertEquals(response.status, 403);
  assertEquals(didFetch, false);
});

Deno.test("unsubscribe fails closed when production configuration is absent", async () => {
  const response = await handleWaitlistUnsubscribe(
    unsubscribeRequest("d".repeat(64)),
    {},
  );

  assertEquals(response.status, 503);
  assertEquals(response.headers.get("Retry-After"), "300");
});

Deno.test("unsubscribe upstream failures remain retryable", async () => {
  const fetcher =
    (() =>
      Promise.reject(new TypeError("network unavailable"))) as typeof fetch;

  const response = await handleWaitlistUnsubscribe(
    unsubscribeRequest("e".repeat(64)),
    environment,
    { fetcher },
  );

  assertEquals(response.status, 503);
  assertEquals(response.headers.get("Retry-After"), "60");
});

Deno.test("unsubscribe page keeps capabilities out of request URLs and history", async () => {
  const script = await Deno.readTextFile(
    new URL("../public/scripts/unsubscribe.js", import.meta.url),
  );

  assert(script.includes("window.location.hash.slice(1)"));
  assert(script.includes("window.history.replaceState"));
  assert(script.includes('fetch("/api/waitlist/unsubscribe"'));
  assert(!script.includes("window.location.search"));
  assert(!script.includes("?token="));
});
