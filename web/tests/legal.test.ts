import { assertEquals } from "@std/assert";
import { resolveLegalIdentity } from "../src/legal.ts";

Deno.test("legal identity remains explicitly incomplete for local builds", () => {
  const identity = resolveLegalIdentity({
    PUBLIC_NINA_LEGAL_ENTITY_NAME: "replace_with_legal_name",
    PUBLIC_NINA_PRIVACY_CONTACT_EMAIL: "not-an-email",
  });

  assertEquals(identity.isProductionComplete, false);
  assertEquals(identity.isLaunchReady, false);
  assertEquals(identity.legalEntityName, undefined);
  assertEquals(identity.privacyContactEmail, "oi@ninai.app");
  assertEquals(identity.documentLabel, "Documento");
  assertEquals(identity.legalEntityKind, undefined);
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

Deno.test("an individual controller who is also the dpo stays complete but is not launch ready", () => {
  const identity = resolveLegalIdentity({
    PUBLIC_NINA_LEGAL_ENTITY_NAME: "Fulano de Tal",
    PUBLIC_NINA_LEGAL_ENTITY_DOCUMENT: "123.456.789-09",
    PUBLIC_NINA_PRIVACY_CONTACT_EMAIL: "privacidade@ninai.app",
    PUBLIC_NINA_DPO_NAME: "  fulano de TAL ",
    PUBLIC_NINA_DPO_CONTACT_EMAIL: "privacidade@ninai.app",
  });

  assertEquals(identity.isProductionComplete, true);
  assertEquals(identity.legalEntityKind, "individual");
  assertEquals(identity.documentLabel, "CPF");
  assertEquals(identity.legalEntityAddress, undefined);
  assertEquals(identity.dpoIsIndependent, false);
  assertEquals(identity.isLaunchReady, false);
});

Deno.test("fourteen document digits read as a company with a cnpj and eleven as a person with a cpf", () => {
  const company = resolveLegalIdentity({
    PUBLIC_NINA_LEGAL_ENTITY_DOCUMENT: "12.345.678/0001-90",
  });
  const person = resolveLegalIdentity({
    PUBLIC_NINA_LEGAL_ENTITY_DOCUMENT: "12345678909",
  });
  const unknown = resolveLegalIdentity({
    PUBLIC_NINA_LEGAL_ENTITY_DOCUMENT: "123-456",
  });

  assertEquals(company.legalEntityKind, "company");
  assertEquals(company.documentLabel, "CNPJ");
  assertEquals(person.legalEntityKind, "individual");
  assertEquals(person.documentLabel, "CPF");
  assertEquals(unknown.legalEntityKind, undefined);
  assertEquals(unknown.documentLabel, "Documento");
});

Deno.test("a company with an address and a dpo who is not the controller is launch ready", () => {
  const identity = resolveLegalIdentity({
    PUBLIC_NINA_LEGAL_ENTITY_NAME: "Nina Tecnologia Ltda.",
    PUBLIC_NINA_LEGAL_ENTITY_DOCUMENT: "12.345.678/0001-90",
    PUBLIC_NINA_LEGAL_ENTITY_ADDRESS:
      "Rua das Flores, 100, sala 2, São Paulo, SP, 01000-000",
    PUBLIC_NINA_PRIVACY_CONTACT_EMAIL: "privacidade@ninai.app",
    PUBLIC_NINA_DPO_NAME: "Beltrana Encarregada",
    PUBLIC_NINA_DPO_CONTACT_EMAIL: "dpo@ninai.app",
  });

  assertEquals(identity.isProductionComplete, true);
  assertEquals(identity.dpoIsIndependent, true);
  assertEquals(
    identity.legalEntityAddress,
    "Rua das Flores, 100, sala 2, São Paulo, SP, 01000-000",
  );
  assertEquals(identity.isLaunchReady, true);
});

Deno.test("a company is not launch ready while its address is missing or a placeholder", () => {
  const base = {
    PUBLIC_NINA_LEGAL_ENTITY_NAME: "Nina Tecnologia Ltda.",
    PUBLIC_NINA_LEGAL_ENTITY_DOCUMENT: "12.345.678/0001-90",
    PUBLIC_NINA_PRIVACY_CONTACT_EMAIL: "privacidade@ninai.app",
    PUBLIC_NINA_DPO_NAME: "Beltrana Encarregada",
    PUBLIC_NINA_DPO_CONTACT_EMAIL: "dpo@ninai.app",
  };

  const missing = resolveLegalIdentity(base);
  const placeholder = resolveLegalIdentity({
    ...base,
    PUBLIC_NINA_LEGAL_ENTITY_ADDRESS: "replace_with_the_controller_address",
  });

  assertEquals(missing.isLaunchReady, false);
  assertEquals(placeholder.legalEntityAddress, undefined);
  assertEquals(placeholder.isLaunchReady, false);
});

Deno.test("an individual controller is never launch ready even with an address and another dpo", () => {
  const identity = resolveLegalIdentity({
    PUBLIC_NINA_LEGAL_ENTITY_NAME: "Fulano de Tal",
    PUBLIC_NINA_LEGAL_ENTITY_DOCUMENT: "123.456.789-09",
    PUBLIC_NINA_LEGAL_ENTITY_ADDRESS: "Rua das Flores, 100, São Paulo, SP",
    PUBLIC_NINA_PRIVACY_CONTACT_EMAIL: "privacidade@ninai.app",
    PUBLIC_NINA_DPO_NAME: "Beltrana Encarregada",
    PUBLIC_NINA_DPO_CONTACT_EMAIL: "dpo@ninai.app",
  });

  assertEquals(identity.dpoIsIndependent, true);
  assertEquals(identity.isLaunchReady, false);
});

Deno.test("a dpo whose name differs from the controller only by accents or punctuation is not independent", () => {
  const identity = resolveLegalIdentity({
    PUBLIC_NINA_LEGAL_ENTITY_NAME: "José da Conceição",
    PUBLIC_NINA_DPO_NAME: "Jose da Conceicao.",
  });

  assertEquals(identity.dpoIsIndependent, false);
});

Deno.test("a dpo with no named controller is never counted as independent", () => {
  const identity = resolveLegalIdentity({
    PUBLIC_NINA_DPO_NAME: "Beltrana Encarregada",
  });

  assertEquals(identity.dpoIsIndependent, false);
});

Deno.test("the report mailbox falls back to the privacy mailbox until a dedicated one is set", () => {
  const fallback = resolveLegalIdentity({
    PUBLIC_NINA_PRIVACY_CONTACT_EMAIL: "privacidade@ninai.app",
  });
  const invalid = resolveLegalIdentity({
    PUBLIC_NINA_PRIVACY_CONTACT_EMAIL: "privacidade@ninai.app",
    PUBLIC_NINA_REPORT_CONTACT_EMAIL: "replace_with_the_report_mailbox",
  });
  const dedicated = resolveLegalIdentity({
    PUBLIC_NINA_PRIVACY_CONTACT_EMAIL: "privacidade@ninai.app",
    PUBLIC_NINA_REPORT_CONTACT_EMAIL: "Denuncia@NinaI.app",
  });

  assertEquals(fallback.reportContactEmail, "privacidade@ninai.app");
  assertEquals(invalid.reportContactEmail, "privacidade@ninai.app");
  assertEquals(dedicated.reportContactEmail, "denuncia@ninai.app");
});

Deno.test("a report mailbox alone never completes the legal identity", () => {
  const identity = resolveLegalIdentity({
    PUBLIC_NINA_REPORT_CONTACT_EMAIL: "denuncia@ninai.app",
  });

  assertEquals(identity.reportContactEmail, "denuncia@ninai.app");
  assertEquals(identity.privacyContactEmail, "oi@ninai.app");
  assertEquals(identity.isProductionComplete, false);
});

Deno.test("both legal pages mark whether the identity is ready for launch", async () => {
  for (const page of ["privacidade.astro", "termos.astro"]) {
    const source = await Deno.readTextFile(
      new URL(`../src/pages/${page}`, import.meta.url),
    );

    assertEquals(
      source.includes(
        'data-legal-launch={legalIdentity.isLaunchReady ? "ready" : "pending"}',
      ),
      true,
      page,
    );
  }
});

Deno.test("the families page publishes the impact assessment summary word for word", async () => {
  const [assessment, page] = await Promise.all([
    Deno.readTextFile(
      new URL(
        "../../docs/privacy/avaliacao-impacto-criancas.md",
        import.meta.url,
      ),
    ),
    Deno.readTextFile(new URL("../src/pages/familias.astro", import.meta.url)),
  ]);
  const collapse = (text: string) => text.replace(/\s+/g, " ").trim();
  const summary = assessment.split("## 10. Published summary")[1]
    .split("\n## ")[0];
  const bullets = summary.split("\n- ").slice(1).map((bullet) =>
    collapse(bullet.split("\n\n")[0])
  );
  const pageText = collapse(page);

  assertEquals(bullets.length, 6);
  for (const bullet of bullets) {
    assertEquals(pageText.includes(bullet), true, bullet);
  }
});
