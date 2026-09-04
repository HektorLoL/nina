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

// Resend verified the contact subdomain, not the apex; the apex would be refused.
export const launchSender = "Nina <nina@contact.ninai.app>";

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

export const launchIconURL = "https://ninai.app/images/email/nina-app-icon.png";

const palette = {
  ground: "#FBFCFD",
  line: "#DFE4EB",
  ink: "#131A24",
  muted: "#5C6675",
  faint: "#646E7C",
  cobalt: "#1B4FD8",
};

const serif = "Fraunces, Georgia, 'Times New Roman', serif";
const sans =
  "-apple-system, BlinkMacSystemFont, Inter, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif";

function paragraph(text: string, color = palette.ink): string {
  return `<p style="margin:0 0 16px 0;font-family:${sans};font-size:16px;line-height:26px;color:${color};">${text}</p>`;
}

export function buildWaitlistLaunchMessage(
  input: WaitlistLaunchMessageInput,
): WaitlistLaunchMessage {
  const install = appStoreURL(input.appStoreID);
  const leave = unsubscribeURL(input.unsubscribeToken);
  const name = greetingName(input.firstName);
  const greeting = name ? `Oi, ${name}.` : "Oi.";
  const preheader = "Pronta para chegar à sua casa.";

  const paragraphs = [
    greeting,
    "A Nina está pronta para chegar à sua casa. Você pediu um aviso quando isso acontecesse, e é este.",
    `Para instalar no iPhone:\n${install}`,
    "Você conta o que precisa ser feito, do jeito que veio na cabeça. Ela transforma em tarefa, lembrete, compra, e espera você confirmar.",
    `Este é o único email desta lista. Se quiser sair dela mesmo assim, é só abrir este link:\n${leave}`,
    "Nina",
  ];

  // One cobalt control on the page, like every screen in the app.
  const html = `<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light">
<title>A Nina chegou</title>
</head>
<body style="margin:0;padding:0;background-color:${palette.ground};">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;font-size:1px;line-height:1px;color:${palette.ground};">${preheader}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:${palette.ground};">
<tr><td align="center" style="padding:40px 16px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;">
<tr><td style="background-color:#FFFFFF;border:1px solid ${palette.line};border-radius:20px;padding:36px 32px 28px 32px;">
<table role="presentation" cellpadding="0" cellspacing="0" border="0">
<tr><td style="padding:0 0 24px 0;"><img src="${launchIconURL}" width="56" height="56" alt="Nina" style="display:block;width:56px;height:56px;border-radius:14px;border:0;"></td></tr>
</table>
<p style="margin:0 0 10px 0;font-family:${sans};font-size:12px;line-height:16px;letter-spacing:1.4px;text-transform:uppercase;color:${palette.faint};">Sua amiga da casa</p>
<h1 style="margin:0 0 24px 0;font-family:${serif};font-weight:400;font-size:34px;line-height:40px;color:${palette.ink};">A Nina chegou</h1>
${paragraph(escapeHTML(greeting))}
${
    paragraph(
      "A Nina está pronta para chegar à sua casa. Você pediu um aviso quando isso acontecesse, e é este.",
    )
  }
${
    paragraph(
      "Você conta o que precisa ser feito, do jeito que veio na cabeça. Ela transforma em tarefa, lembrete, compra, e espera você confirmar.",
      palette.muted,
    )
  }
<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:8px 0 28px 0;">
<tr><td style="background-color:${palette.cobalt};border-radius:999px;"><a href="${install}" style="display:inline-block;padding:14px 24px;font-family:${sans};font-size:16px;line-height:20px;font-weight:600;color:#FFFFFF;text-decoration:none;border-radius:999px;">Instalar no iPhone</a></td></tr>
</table>
<p style="margin:0 0 0 0;font-family:${serif};font-size:18px;line-height:26px;color:${palette.ink};">Nina</p>
</td></tr>
<tr><td style="padding:24px 12px 0 12px;">
<p style="margin:0 0 8px 0;font-family:${sans};font-size:13px;line-height:20px;color:${palette.muted};">Este é o único email desta lista, como prometido em ninai.app. Se quiser sair dela mesmo assim, é só <a href="${leave}" style="color:${palette.muted};text-decoration:underline;">abrir este link</a>.</p>
<p style="margin:0;font-family:${sans};font-size:13px;line-height:20px;color:${palette.muted};">Seus dados ficam em servidores em São Paulo.</p>
</td></tr>
</table>
</td></tr>
</table>
</body>
</html>
`;

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
