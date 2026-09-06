import {
  assert,
  assertEquals,
  assertFalse,
  assertThrows,
} from "jsr:@std/assert@1";
import {
  appAccountTokenMatches,
  appStoreVerificationEnvironments,
  entitlementFromSubscription,
  isAppStoreNotificationRequest,
  isPremiumSyncRequest,
  isUUID,
  mapAppleSubscriptionStatus,
  maxAppStoreRequestBytes,
  readAppStoreJSONRequest,
  verificationFailureDetails,
} from "./app-store.ts";

Deno.test("premium sync request requires a transaction JWS", () => {
  assert(isPremiumSyncRequest({
    signed_transaction_info: "header.payload.signature",
    source: "purchase",
  }));
  assertFalse(isPremiumSyncRequest({ signed_transaction_info: "not-a-jws" }));
  assertFalse(
    isPremiumSyncRequest({ signedTransactionInfo: "header.payload.signature" }),
  );
  assertFalse(isPremiumSyncRequest({
    signed_transaction_info: "header.payload.signature",
    source: "Purchase Screen",
  }));
  assertFalse(isPremiumSyncRequest({
    signed_transaction_info: `${"a".repeat(maxAppStoreRequestBytes)}.b.c`,
  }));
});

Deno.test("notification request requires signedPayload", () => {
  assert(isAppStoreNotificationRequest({
    signedPayload: "header.payload.signature",
  }));
  assertFalse(
    isAppStoreNotificationRequest({
      signed_payload: "header.payload.signature",
    }),
  );
  assertFalse(isAppStoreNotificationRequest({
    signedPayload: "header.pay+load.signature",
  }));
});

Deno.test("uuid validation accepts Supabase user IDs", () => {
  assert(isUUID("10000000-0000-4000-9000-000000000001"));
  assertFalse(isUUID("debug:test-one"));
});

Deno.test("subscription status mapping follows Apple status first", () => {
  const future = Date.now() + 60_000;
  assertEquals(
    mapAppleSubscriptionStatus({ expiresDate: future }, undefined, 1),
    "active",
  );
  assertEquals(
    mapAppleSubscriptionStatus({ expiresDate: future }, undefined, 3),
    "billing_retry",
  );
  assertEquals(
    mapAppleSubscriptionStatus({ expiresDate: future }, undefined, 4),
    "grace_period",
  );
  assertEquals(
    mapAppleSubscriptionStatus({ expiresDate: future, revocationDate: future }),
    "revoked",
  );
});

Deno.test("entitlement response defaults inactive", () => {
  assertEquals(entitlementFromSubscription(null), {
    is_active: false,
    status: "inactive",
    product_id: null,
    expires_at: null,
    will_renew: null,
    environment: null,
    original_transaction_id: null,
    latest_transaction_id: null,
    last_verified_at: null,
  });
});

Deno.test("local App Store environments require explicit configuration", () => {
  const production = appStoreVerificationEnvironments("production")[0];
  const sandbox = appStoreVerificationEnvironments("sandbox")[0];
  const xcode = appStoreVerificationEnvironments("xcode")[0];
  const localTesting = appStoreVerificationEnvironments("local_testing")[0];
  const defaults = appStoreVerificationEnvironments();

  assertEquals(defaults, [production, sandbox]);
  assertFalse(defaults.includes(xcode));
  assertFalse(defaults.includes(localTesting));
  assertEquals(
    appStoreVerificationEnvironments(undefined, String(sandbox)),
    [sandbox, production],
  );
  assertEquals(
    appStoreVerificationEnvironments(undefined, String(xcode)),
    [production, sandbox],
  );
  assertThrows(
    () => appStoreVerificationEnvironments("preview"),
    Error,
    "invalid_app_store_environment",
  );
});

Deno.test("App Store JSON requests require bounded application/json bodies", async () => {
  const valid = await readAppStoreJSONRequest(
    new Request("https://example.test/premium", {
      method: "POST",
      headers: { "Content-Type": "application/json; charset=utf-8" },
      body: JSON.stringify({ signedPayload: "header.payload.signature" }),
    }),
  );
  assert(valid.ok);
  if (valid.ok) {
    assertEquals(valid.value, {
      signedPayload: "header.payload.signature",
    });
  }

  const missingContentType = await readAppStoreJSONRequest(
    new Request("https://example.test/premium", {
      method: "POST",
      body: "{}",
    }),
  );
  assertFalse(missingContentType.ok);
  if (!missingContentType.ok) {
    assertEquals(missingContentType.response.status, 415);
    assertEquals(
      missingContentType.response.headers.get("Cache-Control"),
      "no-store",
    );
  }

  const oversized = await readAppStoreJSONRequest(
    new Request("https://example.test/premium", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: "x".repeat(maxAppStoreRequestBytes + 1),
    }),
  );
  assertFalse(oversized.ok);
  if (!oversized.ok) {
    assertEquals(oversized.response.status, 413);
  }

  const malformed = await readAppStoreJSONRequest(
    new Request("https://example.test/premium", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: "{",
    }),
  );
  assertFalse(malformed.ok);
  if (!malformed.ok) {
    assertEquals(malformed.response.status, 400);
  }
});

Deno.test("Premium endpoints use the shared bounded parser", async () => {
  const endpointURLs = [
    new URL("../premium-subscription-sync/index.ts", import.meta.url),
    new URL("../app-store-server-notifications/index.ts", import.meta.url),
  ];

  for (const endpointURL of endpointURLs) {
    const source = await Deno.readTextFile(endpointURL);
    assert(source.includes("readAppStoreJSONRequest(request)"));
    assert(source.includes('{ Allow: "POST" }'));
    assertFalse(source.includes("await request.json()"));
  }

  const verifierSource = await Deno.readTextFile(
    new URL("./app-store.ts", import.meta.url),
  );
  assert(
    verifierSource.includes(
      "AbortSignal.timeout(rootCertificateTimeoutMilliseconds)",
    ),
  );
  assert(verifierSource.includes("rootCertificatesPromise = undefined"));
});

Deno.test("an app account token matches its user regardless of letter case", () => {
  const userID = "7e3fb20b-4cdb-47cc-936d-99d65f608138";
  assert(
    appAccountTokenMatches("7E3FB20B-4CDB-47CC-936D-99D65F608138", userID),
  );
  assert(appAccountTokenMatches(userID, userID.toUpperCase()));
  assertFalse(
    appAccountTokenMatches("7e3fb20b-4cdb-47cc-936d-99d65f608139", userID),
  );
  assertFalse(appAccountTokenMatches(undefined, userID));
  assertFalse(appAccountTokenMatches("not-a-uuid", userID));
});

Deno.test("verification failures log a status code and a bounded cause, never a body", () => {
  const failure = Object.assign(new Error(""), {
    status: 3,
    cause: new Error("x".repeat(400)),
  });
  const details = verificationFailureDetails(failure);
  assertEquals(details.error, "unknown");
  assertEquals(details.status, "3");
  assertEquals(details.cause?.length, 200);
  assertEquals(verificationFailureDetails("boom"), {
    error: "unknown",
    status: null,
    cause: null,
  });
  assertEquals(verificationFailureDetails(new Error("invalid_bundle_id")), {
    error: "invalid_bundle_id",
    status: null,
    cause: null,
  });
});
