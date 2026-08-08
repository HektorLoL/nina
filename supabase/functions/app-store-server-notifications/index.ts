import { createClient } from "npm:@supabase/supabase-js@2";
import {
  assertTransactionMatchesNina,
  buildSubscriptionUpsert,
  buildTransactionLedgerUpsert,
  entitlementFromSubscription,
  isAppStoreNotificationRequest,
  isUUID,
  jsonResponse,
  parseConfiguredKey,
  readAppStoreJSONRequest,
  verifyNotification,
  verifyRenewalInfo,
  verifyTransaction,
} from "../_shared/app-store.ts";

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") {
    return jsonResponse(
      { error: "method_not_allowed" },
      405,
      { Allow: "POST" },
    );
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL") ?? "";
  const secretKey = parseConfiguredKey(
    "SUPABASE_SECRET_KEYS",
    "SUPABASE_SERVICE_ROLE_KEY",
  );
  if (!supabaseURL || !secretKey) {
    return jsonResponse({ error: "service_not_configured" }, 503);
  }

  const parsedBody = await readAppStoreJSONRequest(request);
  if (!parsedBody.ok) return parsedBody.response;
  const body = parsedBody.value;

  if (!isAppStoreNotificationRequest(body)) {
    return jsonResponse({ error: "invalid_request" }, 400);
  }

  const admin = createClient(supabaseURL, secretKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  try {
    const notification = await verifyNotification(body.signedPayload);
    const signedTransactionInfo = notification.data?.signedTransactionInfo;
    const signedRenewalInfo = notification.data?.signedRenewalInfo;
    const notificationUUID = notification.notificationUUID;

    const transaction = signedTransactionInfo
      ? await verifyTransaction(
        signedTransactionInfo,
        notification.data?.environment,
      )
      : null;
    const renewal = signedRenewalInfo
      ? await verifyRenewalInfo(
        signedRenewalInfo,
        notification.data?.environment,
      )
      : null;

    if (transaction) {
      assertTransactionMatchesNina(transaction);
    }

    let userID = isUUID(transaction?.appAccountToken)
      ? transaction?.appAccountToken ?? null
      : null;
    const originalTransactionID = transaction?.originalTransactionId ??
      renewal?.originalTransactionId ?? null;

    if (!userID && originalTransactionID) {
      const { data: existingSubscription } = await admin
        .from("premium_subscriptions")
        .select("user_id")
        .eq("original_transaction_id", originalTransactionID)
        .maybeSingle();
      userID = isUUID(existingSubscription?.user_id)
        ? existingSubscription.user_id
        : null;
    }

    if (notificationUUID) {
      const { error: notificationError } = await admin
        .from("app_store_server_notifications")
        .upsert({
          notification_uuid: notificationUUID,
          notification_type: notification.notificationType ?? null,
          notification_subtype: notification.subtype ?? null,
          environment: notification.data?.environment ?? null,
          app_apple_id: notification.data?.appAppleId ?? null,
          bundle_id: notification.data?.bundleId ?? null,
          original_transaction_id: originalTransactionID,
          transaction_id: transaction?.transactionId ?? null,
          user_id: userID,
          signed_payload: body.signedPayload,
          payload: notification,
          processed_at: new Date().toISOString(),
        }, { onConflict: "notification_uuid" });
      if (notificationError) {
        console.error(JSON.stringify({
          event: "app_store_notification_record_failed",
          code: notificationError.code,
        }));
      }
    }

    if (!transaction || !signedTransactionInfo) {
      return jsonResponse({ ok: true, ignored: "no_transaction" });
    }

    const ledgerUpsert = buildTransactionLedgerUpsert({
      userID,
      signedTransactionInfo,
      transaction,
      source: "app_store_notification",
    });
    const subscriptionUpsert = buildSubscriptionUpsert({
      userID,
      signedTransactionInfo,
      transaction,
      signedRenewalInfo,
      renewal,
      notification,
      source: "app_store_notification",
    });

    const { error: ledgerError } = await admin
      .from("premium_subscription_transactions")
      .upsert(ledgerUpsert, { onConflict: "transaction_id" });
    if (ledgerError) {
      console.error(JSON.stringify({
        event: "app_store_notification_ledger_failed",
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
        event: "app_store_notification_subscription_failed",
        code: subscriptionError.code,
      }));
      return jsonResponse({ error: "subscription_sync_failed" }, 503);
    }

    return jsonResponse({
      ok: true,
      entitlement: entitlementFromSubscription(subscription),
    });
  } catch (error) {
    console.error(JSON.stringify({
      event: "app_store_notification_verification_failed",
      error: error instanceof Error ? error.message : "unknown",
    }));
    return jsonResponse({ error: "notification_verification_failed" }, 400);
  }
});
