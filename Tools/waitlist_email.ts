export interface WaitlistLaunchMessageInput {
  firstName?: string | null;
  unsubscribeToken: string;
  appStoreID: string;
}

export interface WaitlistLaunchMessage {
  subject: string;
  text: string;
  html: string;
}

export interface WaitlistRecipient {
  email: string;
  first_name?: string | null;
  unsubscribe_token: string;
}

export interface CampaignDeliveryReport {
  sent: number;
  failed: number;
}

export interface CampaignDeliveryDependencies {
  campaign: string;
  appStoreID: string;
  recipients: WaitlistRecipient[];
  send: (
    recipient: WaitlistRecipient,
    message: WaitlistLaunchMessage,
  ) => Promise<string>;
  record: (recipient: WaitlistRecipient, messageID: string) => Promise<void>;
  pause?: () => Promise<void>;
  reportFailure?: (status: string) => void;
}

const unsubscribeTokenPattern = /^[0-9a-f]{64}$/u;
const appStoreIDPattern = /^[1-9][0-9]{5,}$/u;
export const campaignPattern = /^[a-z0-9._-]{1,40}$/u;

export const launchSender = "Nina <nina@ninai.app>";

export function appStoreURL(appStoreID: string): string {
  if (!appStoreIDPattern.test(appStoreID)) {
    throw new Error("app_store_id_invalid");
  }
  return `https://apps.apple.com/br/app/id${appStoreID}`;
}

// The token travels only in the fragment: a path or query would land it in access logs.
export function unsubscribeURL(unsubscribeToken: string): string {
  if (!unsubscribeTokenPattern.test(unsubscribeToken)) {
    throw new Error("unsubscribe_token_invalid");
  }
  return `https://ninai.app/unsubscribe/#${unsubscribeToken}`;
}

function escapeHTML(value: string): string {
  return value.replace(/[&<>"']/gu, (character) => {
    switch (character) {
      case "&":
        return "&amp;";
      case "<":
        return "&lt;";
      case ">":
        return "&gt;";
      case '"':
        return "&quot;";
      default:
        return "&#39;";
    }
  });
}

function greetingName(firstName: string | null | undefined): string | null {
  const cleaned = (firstName ?? "").replace(/\s+/gu, " ").trim();
  return cleaned.length > 0 && cleaned.length <= 80 ? cleaned : null;
}

export function buildWaitlistLaunchMessage(
  input: WaitlistLaunchMessageInput,
): WaitlistLaunchMessage {
  const install = appStoreURL(input.appStoreID);
  const leave = unsubscribeURL(input.unsubscribeToken);
  const name = greetingName(input.firstName);
  const greeting = name ? `Oi, ${name}.` : "Oi.";

  const paragraphs = [
    greeting,
    "A Nina está pronta para chegar à sua casa. Você pediu um aviso quando isso acontecesse, e é este.",
    `Para instalar no iPhone:\n${install}`,
    `Este é o único email desta lista. Se quiser sair dela mesmo assim, é só abrir este link:\n${leave}`,
    "Nina",
  ];

  const html = [
    `<p>${escapeHTML(greeting)}</p>`,
    "<p>A Nina está pronta para chegar à sua casa. Você pediu um aviso quando isso acontecesse, e é este.</p>",
    `<p>Para instalar no iPhone:<br><a href="${install}">${install}</a></p>`,
    `<p>Este é o único email desta lista. Se quiser sair dela mesmo assim, é só abrir este link:<br><a href="${leave}">${leave}</a></p>`,
    "<p>Nina</p>",
  ].join("\n");

  return {
    subject: "A Nina chegou",
    text: paragraphs.join("\n\n") + "\n",
    html,
  };
}

export async function deliverCampaign(
  dependencies: CampaignDeliveryDependencies,
): Promise<CampaignDeliveryReport> {
  if (!campaignPattern.test(dependencies.campaign)) {
    throw new Error("campaign_invalid");
  }

  const report: CampaignDeliveryReport = { sent: 0, failed: 0 };

  for (const recipient of dependencies.recipients) {
    let message: WaitlistLaunchMessage;
    try {
      message = buildWaitlistLaunchMessage({
        firstName: recipient.first_name,
        unsubscribeToken: recipient.unsubscribe_token,
        appStoreID: dependencies.appStoreID,
      });
    } catch (error) {
      report.failed += 1;
      dependencies.reportFailure?.(
        error instanceof Error ? error.message : "message_build_failed",
      );
      continue;
    }

    // A send that was not recorded is retried next run, so the provider key dedupes it.
    try {
      const messageID = await dependencies.send(recipient, message);
      await dependencies.record(recipient, messageID);
      report.sent += 1;
    } catch (error) {
      report.failed += 1;
      dependencies.reportFailure?.(
        error instanceof Error ? error.message : "send_failed",
      );
    }

    await dependencies.pause?.();
  }

  return report;
}
