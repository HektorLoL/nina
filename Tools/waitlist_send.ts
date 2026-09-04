import { parseEnvironmentFile } from "./production_preflight.ts";
import {
  buildWaitlistLaunchMessage,
  campaignPattern,
  deliverCampaign,
  launchSender,
  type WaitlistLaunchMessage,
  type WaitlistRecipient,
} from "./waitlist_email.ts";

interface Options {
  campaign: string;
  envFile: string;
  dryRun: boolean;
  testTo: string | null;
}

interface Settings {
  supabaseURL: URL;
  secretKey: string;
  resendKey: string;
  appStoreID: string;
}

const resendEndpoint = "https://api.resend.com/emails";
const sendPauseMilliseconds = 600;
const requestTimeoutMilliseconds = 15_000;

function usage(): never {
  console.error(
    "usage: deno task waitlist:send --campaign <slug> [--dry-run] [--test-to <address>] [--env-file config/production.env]",
  );
  Deno.exit(2);
}

function parseOptions(args: string[]): Options {
  const options: Options = {
    campaign: "",
    envFile: "config/production.env",
    dryRun: false,
    testTo: null,
  };

  for (let index = 0; index < args.length; index += 1) {
    const argument = args[index];
    if (argument === "--dry-run") {
      options.dryRun = true;
    } else if (argument === "--campaign") {
      options.campaign = args[index + 1] ?? "";
      index += 1;
    } else if (argument === "--test-to") {
      options.testTo = args[index + 1] ?? null;
      index += 1;
    } else if (argument === "--env-file") {
      options.envFile = args[index + 1] ?? options.envFile;
      index += 1;
    } else {
      usage();
    }
  }

  if (!campaignPattern.test(options.campaign)) usage();
  return options;
}

async function loadSettings(envFile: string): Promise<Settings> {
  const environment = parseEnvironmentFile(await Deno.readTextFile(envFile));
  const value = (key: string) => environment[key]?.trim() ?? "";

  const supabaseURL = new URL(value("NINA_SUPABASE_URL"));
  if (supabaseURL.protocol !== "https:") {
    throw new Error("supabase_url_invalid");
  }

  const secretKey = value("NINA_SUPABASE_SECRET_KEY");
  if (!secretKey.startsWith("sb_secret_") || secretKey.includes("replace")) {
    throw new Error("supabase_secret_key_invalid");
  }

  const resendKey = value("NINA_RESEND_API_KEY");
  if (!resendKey.startsWith("re_") || resendKey.includes("replace")) {
    throw new Error("resend_key_invalid");
  }

  const appStoreID = value("PUBLIC_NINA_APP_STORE_ID");
  if (!/^[1-9][0-9]{5,}$/u.test(appStoreID)) {
    throw new Error("app_store_id_invalid");
  }

  return { supabaseURL, secretKey, resendKey, appStoreID };
}

async function rpc<Result>(
  settings: Settings,
  name: string,
  body: Record<string, unknown>,
): Promise<Result> {
  const response = await fetch(
    new URL(`/rest/v1/rpc/${name}`, settings.supabaseURL),
    {
      method: "POST",
      signal: AbortSignal.timeout(requestTimeoutMilliseconds),
      headers: {
        apikey: settings.secretKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    },
  );
  if (!response.ok) throw new Error(`rpc_${name}_failed_${response.status}`);
  return await response.json() as Result;
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function sendThroughResend(
  settings: Settings,
  campaign: string,
  recipient: WaitlistRecipient,
  message: WaitlistLaunchMessage,
): Promise<string> {
  const response = await fetch(resendEndpoint, {
    method: "POST",
    signal: AbortSignal.timeout(requestTimeoutMilliseconds),
    headers: {
      Authorization: `Bearer ${settings.resendKey}`,
      "Content-Type": "application/json",
      "Idempotency-Key": `${campaign}/${await sha256Hex(recipient.email)}`,
    },
    body: JSON.stringify({
      from: launchSender,
      to: [recipient.email],
      subject: message.subject,
      text: message.text,
      html: message.html,
    }),
  });
  const result = await response.json().catch(() => ({})) as {
    id?: unknown;
    name?: unknown;
  };
  // The provider's error name is a stable code; its message can quote the address.
  if (!response.ok) {
    const name = typeof result.name === "string" ? `_${result.name}` : "";
    throw new Error(`resend_failed_${response.status}${name}`);
  }
  return typeof result.id === "string" ? result.id : "";
}

async function main(): Promise<void> {
  const options = parseOptions(Deno.args);
  const settings = await loadSettings(options.envFile);

  if (options.testTo) {
    const message = buildWaitlistLaunchMessage({
      firstName: null,
      unsubscribeToken: "0".repeat(64),
      appStoreID: settings.appStoreID,
    });
    const messageID = await sendThroughResend(
      settings,
      `test-${Date.now()}`,
      { email: options.testTo, unsubscribe_token: "0".repeat(64) },
      message,
    );
    console.info(JSON.stringify({ event: "waitlist_test_sent", messageID }));
    return;
  }

  // The list is read immediately before sending so a withdrawal is honored to the second.
  const recipients = await rpc<WaitlistRecipient[]>(
    settings,
    "list_waitlist_recipients",
    { p_campaign: options.campaign },
  );

  if (options.dryRun) {
    console.info(JSON.stringify({
      event: "waitlist_send_dry_run",
      campaign: options.campaign,
      recipients: recipients.length,
    }));
    return;
  }

  const report = await deliverCampaign({
    campaign: options.campaign,
    appStoreID: settings.appStoreID,
    recipients,
    send: (recipient, message) =>
      sendThroughResend(settings, options.campaign, recipient, message),
    record: async (recipient, messageID) => {
      await rpc(settings, "record_waitlist_delivery", {
        p_email: recipient.email,
        p_campaign: options.campaign,
        p_provider_message_id: messageID || null,
      });
    },
    pause: () =>
      new Promise((resolve) => setTimeout(resolve, sendPauseMilliseconds)),
    reportFailure: (status) =>
      console.error(JSON.stringify({ event: "waitlist_send_failed", status })),
  });

  console.info(JSON.stringify({
    event: "waitlist_send_finished",
    campaign: options.campaign,
    sent: report.sent,
    failed: report.failed,
  }));

  if (report.failed > 0) Deno.exit(1);
}

if (import.meta.main) {
  await main();
}
