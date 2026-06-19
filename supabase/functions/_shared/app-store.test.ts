import {
  assert,
  assertEquals,
  assertFalse,
} from "jsr:@std/assert@1";
import {
  entitlementFromSubscription,
  isAppStoreNotificationRequest,
  isPremiumSyncRequest,
  isUUID,
  mapAppleSubscriptionStatus,
} from "./app-store.ts";

Deno.test("premium sync request requires a transaction JWS", () => {
  assert(isPremiumSyncRequest({
    signed_transaction_info: "header.payload.signature",
    source: "purchase",
  }));
  assertFalse(isPremiumSyncRequest({ signed_transaction_info: "not-a-jws" }));
  assertFalse(isPremiumSyncRequest({ signedTransactionInfo: "header.payload.signature" }));
});

Deno.test("notification request requires signedPayload", () => {
  assert(isAppStoreNotificationRequest({
    signedPayload: "header.payload.signature",
  }));
  assertFalse(isAppStoreNotificationRequest({ signed_payload: "header.payload.signature" }));
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
