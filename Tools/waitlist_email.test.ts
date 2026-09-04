import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import {
  buildWaitlistLaunchMessage,
  deliverCampaign,
  type WaitlistRecipient,
} from "./waitlist_email.ts";

const token = "ab".repeat(32);
const appStoreID = "6808423946";

Deno.test("the launch message greets by first name and carries both links", () => {
  const message = buildWaitlistLaunchMessage({
    firstName: "  Ana   Maria ",
    unsubscribeToken: token,
    appStoreID,
  });

  assertEquals(message.subject, "A Nina chegou");
  assert(message.text.startsWith("Oi, Ana Maria.\n\n"));
  assert(message.text.includes("https://apps.apple.com/br/app/id6808423946"));
  assert(message.text.includes(`https://ninai.app/unsubscribe/#${token}`));
  assert(
    message.html.includes(`href="https://ninai.app/unsubscribe/#${token}"`),
  );
});

Deno.test("a missing name falls back to a plain greeting", () => {
  const message = buildWaitlistLaunchMessage({
    firstName: null,
    unsubscribeToken: token,
    appStoreID,
  });
  assert(message.text.startsWith("Oi.\n\n"));
});

Deno.test("the launch message keeps Nina's register", () => {
  const message = buildWaitlistLaunchMessage({
    firstName: "Bia",
    unsubscribeToken: token,
    appStoreID,
  });
  assert(!message.text.includes("!"));
  assert(!/[\u{1F300}-\u{1FAFF}]/u.test(message.text));
  assert(message.text.includes("único email desta lista"));
});

Deno.test("names are escaped before reaching the HTML body", () => {
  const message = buildWaitlistLaunchMessage({
    firstName: "<b>Ana</b>",
    unsubscribeToken: token,
    appStoreID,
  });
  assert(!message.html.includes("<b>Ana</b>"));
  assert(message.html.includes("&lt;b&gt;Ana&lt;/b&gt;"));
});

Deno.test("the unsubscribe token only ever travels in the fragment", () => {
  const message = buildWaitlistLaunchMessage({
    firstName: null,
    unsubscribeToken: token,
    appStoreID,
  });
  const links = message.text.match(/https:\/\/ninai\.app\/[^\s]+/gu) ?? [];
  assertEquals(links, [`https://ninai.app/unsubscribe/#${token}`]);
});

Deno.test("a malformed token or store id refuses to build a message", () => {
  assertThrows(() =>
    buildWaitlistLaunchMessage({
      unsubscribeToken: "short",
      appStoreID,
    })
  );
  assertThrows(() =>
    buildWaitlistLaunchMessage({
      unsubscribeToken: token,
      appStoreID: "replace_with_the_numeric_app_store_id",
    })
  );
});

Deno.test("a campaign records each success, survives a failure, and never resends", async () => {
  const recipients: WaitlistRecipient[] = [
    { email: "a@example.com", first_name: "A", unsubscribe_token: token },
    { email: "b@example.com", first_name: null, unsubscribe_token: token },
    { email: "c@example.com", first_name: "C", unsubscribe_token: "bad" },
    { email: "d@example.com", first_name: "D", unsubscribe_token: token },
  ];
  const sent: string[] = [];
  const recorded: Array<[string, string]> = [];
  const failures: string[] = [];

  const report = await deliverCampaign({
    campaign: "launch-test",
    appStoreID,
    recipients,
    send: (recipient) => {
      sent.push(recipient.email);
      if (recipient.email === "b@example.com") {
        return Promise.reject(new Error("resend_failed_500"));
      }
      return Promise.resolve(`msg-${recipient.email}`);
    },
    record: (recipient, messageID) => {
      recorded.push([recipient.email, messageID]);
      return Promise.resolve();
    },
    reportFailure: (status) => failures.push(status),
  });

  assertEquals(report, { sent: 2, failed: 2 });
  assertEquals(sent, ["a@example.com", "b@example.com", "d@example.com"]);
  assertEquals(recorded, [
    ["a@example.com", "msg-a@example.com"],
    ["d@example.com", "msg-d@example.com"],
  ]);
  assertEquals(failures, ["resend_failed_500", "unsubscribe_token_invalid"]);
});

Deno.test("a campaign name must be a short lowercase slug", async () => {
  await assertRejects(() =>
    deliverCampaign({
      campaign: "Launch 2026",
      appStoreID,
      recipients: [],
      send: () => Promise.resolve(""),
      record: () => Promise.resolve(),
    })
  );
});

Deno.test("the sender never logs an address, a name, or a token", async () => {
  const source = await Deno.readTextFile(
    new URL("./waitlist_send.ts", import.meta.url),
  );
  const logStatements = source.match(/console\.(?:info|error)\([^;]*\)/gsu) ??
    [];
  assert(logStatements.length >= 3);
  for (const statement of logStatements) {
    assert(!/email|first_name|unsubscribe_token|recipient\./u.test(statement));
  }
  assert(source.includes('"Idempotency-Key"'));
  assert(source.includes("list_waitlist_recipients"));
  assert(source.includes("record_waitlist_delivery"));
});
