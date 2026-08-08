import { assertEquals } from "@std/assert";
import { resolveLegalIdentity } from "../src/legal.ts";

Deno.test("legal identity remains explicitly incomplete for local builds", () => {
  const identity = resolveLegalIdentity({
    PUBLIC_NINA_LEGAL_ENTITY_NAME: "replace_with_legal_name",
    PUBLIC_NINA_PRIVACY_CONTACT_EMAIL: "not-an-email",
  });

  assertEquals(identity.isProductionComplete, false);
  assertEquals(identity.legalEntityName, undefined);
  assertEquals(identity.privacyContactEmail, "oi@ninai.app");
});

Deno.test("legal identity becomes complete only with every public field", () => {
  const identity = resolveLegalIdentity({
    PUBLIC_NINA_LEGAL_ENTITY_NAME: "Nina Tecnologia Ltda.",
    PUBLIC_NINA_LEGAL_ENTITY_DOCUMENT: "12.345.678/0001-90",
    PUBLIC_NINA_PRIVACY_CONTACT_EMAIL: "privacidade@ninai.app",
    PUBLIC_NINA_DPO_NAME: "Responsável de Privacidade",
    PUBLIC_NINA_DPO_CONTACT_EMAIL: "dpo@ninai.app",
  });

  assertEquals(identity.isProductionComplete, true);
  assertEquals(identity.privacyContactEmail, "privacidade@ninai.app");
  assertEquals(identity.dpoContactEmail, "dpo@ninai.app");
});
