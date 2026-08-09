import { assert, assertEquals, assertFalse, assertThrows } from "@std/assert";
import {
  deploymentChecks,
  iosArtifactChecks,
  type IOSArtifactSnapshot,
  isPublishableSupabaseKey,
  isSecretSupabaseKey,
  parseEnvironmentFile,
  type PreflightEnvironment,
  productionEnvironmentChecks,
  type RepositoryFacts,
} from "./production_preflight.ts";

const facts: RepositoryFacts = {
  bundleID: "com.heitor.nina",
  teamID: "97PL8KQA8L",
  productIDs: [
    "com.heitor.nina.premium.monthly",
    "com.heitor.nina.premium.yearly",
  ],
  publicBaseURL: "https://ninai.app",
};

function encodedSegment(value: unknown): string {
  return btoa(JSON.stringify(value))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

function jwt(role: string): string {
  return `${encodedSegment({ alg: "HS256" })}.${
    encodedSegment({ role })
  }.signature`;
}

function validEnvironment(): PreflightEnvironment {
  return {
    NINA_PUBLIC_BASE_URL: "https://ninai.app",
    NINA_SUPABASE_URL: "https://project-ref.supabase.co",
    NINA_SUPABASE_PUBLISHABLE_KEY:
      `sb_${"publishable"}_${"A1b2C3d4E5f6G7h8I9j0"}`,
    NINA_SUPABASE_SECRET_KEY: `sb_${"secret"}_${"Z9y8X7w6V5u4T3s2R1q0"}`,
    NINA_WAITLIST_HASH_SALT: "aB3$dE5&fG7!hJ9*kL1@mN3#pQ5%rS7^",
    OPENAI_API_KEY: `sk-${"p".repeat(48)}`,
    NINA_APP_BUNDLE_ID: facts.bundleID,
    NINA_APPLE_TEAM_ID: facts.teamID,
    NINA_APP_APPLE_ID: "1234567890",
    PUBLIC_NINA_APP_STORE_ID: "1234567890",
    NINA_PREMIUM_PRODUCT_IDS: facts.productIDs.join(","),
    NINA_APP_STORE_ENVIRONMENT: "production",
    NINA_APP_STORE_ONLINE_CHECKS: "true",
    NINA_AI_V2_ENABLED: "NO",
    PUBLIC_NINA_LEGAL_ENTITY_NAME: "Nina Tecnologia Ltda.",
    PUBLIC_NINA_LEGAL_ENTITY_DOCUMENT: "12.345.678/0001-90",
    PUBLIC_NINA_PRIVACY_CONTACT_EMAIL: "privacidade@ninai.app",
    PUBLIC_NINA_DPO_NAME: "Responsável de Privacidade",
    PUBLIC_NINA_DPO_CONTACT_EMAIL: "privacidade@ninai.app",
  };
}

function validArtifact(): IOSArtifactSnapshot {
  const environment = validEnvironment();
  return {
    info: {
      CFBundleIdentifier: facts.bundleID,
      CFBundleShortVersionString: "1.0",
      CFBundleVersion: "1",
      CFBundleExecutable: "Nina",
      NINA_SUPABASE_URL: environment.NINA_SUPABASE_URL,
      NINA_SUPABASE_PUBLISHABLE_KEY: environment.NINA_SUPABASE_PUBLISHABLE_KEY,
      NINA_PREMIUM_PRODUCT_IDS: environment.NINA_PREMIUM_PRODUCT_IDS,
      NINA_AI_V2_ENABLED: environment.NINA_AI_V2_ENABLED,
    },
    archiveInfo: {
      ApplicationProperties: {
        CFBundleIdentifier: facts.bundleID,
        Team: facts.teamID,
        SigningIdentity: "Apple Distribution",
      },
    },
    files: ["Nina", "PrivacyInfo.xcprivacy", "Assets.car"],
    isArchive: true,
    scanComplete: true,
    containsServerCredential: false,
  };
}

Deno.test("parseEnvironmentFile supports export, quotes, and comments", () => {
  const parsed = parseEnvironmentFile(`
    # release values
    export NINA_PUBLIC_BASE_URL="https://ninai.app"
    NINA_AI_V2_ENABLED=NO # explicit release decision
    PUBLIC_NINA_DPO_NAME='Responsável de Privacidade'
  `);

  assertEquals(parsed, {
    NINA_PUBLIC_BASE_URL: "https://ninai.app",
    NINA_AI_V2_ENABLED: "NO",
    PUBLIC_NINA_DPO_NAME: "Responsável de Privacidade",
  });
});

Deno.test("parseEnvironmentFile rejects ambiguous duplicate keys", () => {
  assertThrows(
    () => parseEnvironmentFile("NINA_AI_V2_ENABLED=NO\nNINA_AI_V2_ENABLED=YES"),
    Error,
    "Duplicate environment key",
  );
});

Deno.test("Supabase key validation separates client and server roles", () => {
  assert(isPublishableSupabaseKey(jwt("anon")));
  assert(!isPublishableSupabaseKey(jwt("service_role")));
  assert(isSecretSupabaseKey(jwt("service_role")));
  assert(!isSecretSupabaseKey(jwt("anon")));
  assert(!isSecretSupabaseKey("sb_secret_replace_with_a_real_key"));
});

Deno.test("production environment accepts a complete release configuration", () => {
  const checks = productionEnvironmentChecks(validEnvironment(), facts);
  assertEquals(
    checks.filter((result) => result.status === "failure"),
    [],
  );
});

Deno.test("production environment rejects swapped keys and launch placeholders", () => {
  const environment = validEnvironment();
  environment.NINA_SUPABASE_PUBLISHABLE_KEY = jwt("service_role");
  environment.NINA_SUPABASE_SECRET_KEY = jwt("anon");
  environment.NINA_APP_APPLE_ID = "replace_with_numeric_id";
  environment.PUBLIC_NINA_LEGAL_ENTITY_NAME = "replace with legal name";
  environment.PUBLIC_NINA_PRIVACY_CONTACT_EMAIL = "oi@ninai.app";

  const failedIDs = productionEnvironmentChecks(environment, facts)
    .filter((result) => result.status === "failure")
    .map((result) => result.id);

  assert(failedIDs.includes("environment.publishable-key"));
  assert(failedIDs.includes("environment.secret-key"));
  assert(failedIDs.includes("environment.apple-id"));
  assert(failedIDs.includes("environment.legal-identity"));
  assert(failedIDs.includes("environment.privacy-contacts"));
});

Deno.test("the website install link must name the same app the server verifies", () => {
  const environment = validEnvironment();
  environment.PUBLIC_NINA_APP_STORE_ID = "9876543210";

  const failedIDs = productionEnvironmentChecks(environment, facts)
    .filter((result) => result.status === "failure")
    .map((result) => result.id);

  assert(failedIDs.includes("environment.app-store-id-parity"));
  assertFalse(failedIDs.includes("environment.apple-id"));
});

Deno.test("iOS artifact accepts a matching signed release archive", () => {
  const checks = iosArtifactChecks(
    validArtifact(),
    validEnvironment(),
    facts,
  );
  assertEquals(
    checks.filter((result) => result.status !== "pass"),
    [],
  );
});

Deno.test("iOS artifact rejects unresolved settings, drift, and server credentials", () => {
  const artifact = validArtifact();
  artifact.info.NINA_SUPABASE_PUBLISHABLE_KEY = `sb_${"secret"}_${
    "S".repeat(32)
  }`;
  artifact.info.NINA_PREMIUM_PRODUCT_IDS = "com.heitor.nina.premium.unknown";
  artifact.info.NINA_AI_V2_ENABLED = "$(NINA_AI_V2_ENABLED)";
  artifact.containsServerCredential = true;
  const failedIDs = iosArtifactChecks(
    artifact,
    validEnvironment(),
    facts,
  )
    .filter((result) => result.status === "failure")
    .map((result) => result.id);

  assert(failedIDs.includes("artifact.publishable-key"));
  assert(failedIDs.includes("artifact.products"));
  assert(failedIDs.includes("artifact.ai-release-decision"));
  assert(failedIDs.includes("artifact.resolved-settings"));
  assert(failedIDs.includes("artifact.credential-scan"));
});

Deno.test("online deployment checks verify health, policy, headers, and AASA", async () => {
  const environment = validEnvironment();
  const secureHeaders = {
    "Content-Security-Policy": "default-src 'self'; object-src 'none'",
    "Strict-Transport-Security": "max-age=31536000",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "strict-origin-when-cross-origin",
  };
  const fetcher = (input: string | URL): Promise<Response> => {
    const path = new URL(input).pathname;
    if (path === "/api/health") {
      return Promise.resolve(Response.json({
        status: "ok",
        checks: { inviteLookup: true, waitlist: true },
      }));
    }
    if (path === "/privacidade/") {
      return Promise.resolve(
        new Response(
          `<article data-legal-status="complete">${environment.PUBLIC_NINA_LEGAL_ENTITY_NAME} ${environment.PUBLIC_NINA_DPO_CONTACT_EMAIL}</article>`,
        ),
      );
    }
    if (path === "/unsubscribe/") {
      return Promise.resolve(
        new Response(
          '<meta name="robots" content="noindex,nofollow">',
        ),
      );
    }
    if (path === "/.well-known/apple-app-site-association") {
      return Promise.resolve(Response.json({
        applinks: {
          details: [{ appIDs: [`${facts.teamID}.${facts.bundleID}`] }],
        },
      }, { headers: { "Content-Type": "application/json" } }));
    }
    return Promise.resolve(
      new Response("<title>Nina</title>", {
        headers: secureHeaders,
      }),
    );
  };

  const checks = await deploymentChecks(environment, facts, fetcher);
  assertEquals(
    checks.filter((result) => result.status === "failure"),
    [],
  );
});

Deno.test("online deployment checks fail closed on degraded health", async () => {
  const environment = validEnvironment();
  const fetcher = (input: string | URL): Promise<Response> => {
    const path = new URL(input).pathname;
    if (path === "/api/health") {
      return Promise.resolve(Response.json(
        { status: "degraded", checks: { waitlist: false } },
        { status: 503 },
      ));
    }
    if (path === "/.well-known/apple-app-site-association") {
      return Promise.resolve(Response.json({ applinks: { details: [] } }));
    }
    return Promise.resolve(new Response("Nina"));
  };

  const checks = await deploymentChecks(environment, facts, fetcher);
  const health = checks.find((result) => result.id === "deployment.health");
  assertEquals(health?.status, "failure");
});
