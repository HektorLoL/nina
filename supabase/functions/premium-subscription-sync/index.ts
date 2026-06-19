import { createClient } from "npm:@supabase/supabase-js@2";
import {
  assertTransactionMatchesNina,
  buildSubscriptionUpsert,
  buildTransactionLedgerUpsert,
  entitlementFromSubscription,
  isPremiumSyncRequest,
  isUUID,
  jsonResponse,
  parseConfiguredKey,
  verifyTransaction,
} from "../_shared/app-store.ts";

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL") ?? "";
  const publishableKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const secretKey = parseConfiguredKey(
    "SUPABASE_SECRET_KEYS",
    "SUPABASE_SERVICE_ROLE_KEY",
  );
  if (!supabaseURL || !publishableKey || !secretKey) {
    return jsonResponse({ error: "service_not_configured" }, 503);
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  if (!isPremiumSyncRequest(body)) {
    return jsonResponse({ error: "invalid_request" }, 400);
  }

  const authHeader = request.headers.get("Authorization") ?? "";
  const userClient = createClient(supabaseURL, publishableKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  const userID = userData.user?.id;
  if (userError || !isUUID(userID)) {
    return jsonResponse({ error: "not_authenticated" }, 401);
  }

  const admin = createClient(supabaseURL, secretKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  try {
    const transaction = await verifyTransaction(body.signed_transaction_info);
    assertTransactionMatchesNina(transaction);

    if (transaction.appAccountToken !== userID) {
      return jsonResponse({ error: "app_account_token_mismatch" }, 403);
    }

    const source = body.source?.slice(0, 80) || "app_sync";
    const subscriptionUpsert = buildSubscriptionUpsert({
      userID,
      signedTransactionInfo: body.signed_transaction_info,
      transaction,
      source,
    });
    const transactionUpsert = buildTransactionLedgerUpsert({
      userID,
      signedTransactionInfo: body.signed_transaction_info,
      transaction,
      source,
    });

    const { error: ledgerError } = await admin
      .from("premium_subscription_transactions")
      .upsert(transactionUpsert, { onConflict: "transaction_id" });
    if (ledgerError) {
      console.error(JSON.stringify({
        event: "premium_transaction_ledger_failed",
        code: ledgerError.code,
      }));
      return jsonResponse({ error: "transaction_ledger_failed" }, 503);
    }

    const { data: subscription, error: subscriptionError } = await admin
      .from("premium_subscriptions")
      .upsert(subscriptionUpsert, { onConflict: "original_transaction_id" })
      .select()
      .single();
    if (subscriptionError) {
      console.error(JSON.stringify({
        event: "premium_subscription_upsert_failed",
        code: subscriptionError.code,
      }));
      return jsonResponse({ error: "subscription_sync_failed" }, 503);
    }

    return jsonResponse({
      entitlement: entitlementFromSubscription(subscription),
    });
  } catch (error) {
    console.error(JSON.stringify({
      event: "premium_sync_verification_failed",
      error: error instanceof Error ? error.message : "unknown",
    }));
    return jsonResponse({ error: "transaction_verification_failed" }, 400);
  }
});
