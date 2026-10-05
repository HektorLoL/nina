import { assert, assertEquals, assertFalse, assertThrows } from "@std/assert";
import {
  ageAssuranceEntitlementsPresent,
  appleScopeRequests,
  asksAppleForTheNameAlone,
  containsDebugSignIn,
  deploymentChecks,
  deploymentTargetsAtLeast,
  iosArtifactChecks,
  type IOSArtifactSnapshot,
  isAppleOnlySignIn,
  isPublishableSupabaseKey,
  isSecretSupabaseKey,
  legalAgeRuleHolds,
  looksLikeSecret,
  nonAppleSignInCalls,
  parseEnvironmentFile,
  pinnedSupabaseCLIVersions,
  type PreflightEnvironment,
  premiumTransactionFinishes,
  productionEnvironmentChecks,
  ratingCodes,
  ratingConstantsAgree,
  ratingMarkOffenders,
  type RepositoryFacts,
  retentionClaimOffenders,
  signInProviderCheck,
  versionAtLeast,
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
    NINA_APP_STORE_ONLINE_CHECKS: "true",
    NINA_AI_V2_ENABLED: "NO",
    NINA_ATTACHMENTS_ENABLED: "NO",
    PUBLIC_NINA_LEGAL_ENTITY_NAME: "Nina Tecnologia Ltda.",
    PUBLIC_NINA_LEGAL_ENTITY_DOCUMENT: "12.345.678/0001-90",
    PUBLIC_NINA_PRIVACY_CONTACT_EMAIL: "privacidade@ninai.app",
    PUBLIC_NINA_DPO_NAME: "Responsável de Privacidade",
    PUBLIC_NINA_DPO_CONTACT_EMAIL: "privacidade@ninai.app",
    PUBLIC_NINA_LEGAL_ENTITY_ADDRESS:
      "Avenida Paulista, 1000, São Paulo, SP, 01310-100",
    NINA_CONTROLLER_DECISION_MAKERS: "Heitor Castello",
    NINA_APP_ATTEST_MODE: "production",
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
      NINA_ATTACHMENTS_ENABLED: environment.NINA_ATTACHMENTS_ENABLED,
      MinimumOSVersion: "26.4",
    },
    entitlements: {
      "com.apple.developer.applesignin": ["Default"],
      "com.apple.developer.declared-age-range": true,
      "com.apple.developer.devicecheck.appattest-environment": "production",
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
    containsDebugSignIn: false,
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

Deno.test("shipping household documents abroad must be an explicit release decision", () => {
  const environment = validEnvironment();
  delete environment.NINA_ATTACHMENTS_ENABLED;

  const failedIDs = productionEnvironmentChecks(environment, facts)
    .filter((result) => result.status === "failure")
    .map((result) => result.id);

  assert(failedIDs.includes("environment.attachment-release-decision"));
});

Deno.test("a build that ships documents against an inventory that withholds them fails", () => {
  const artifact = validArtifact();
  artifact.info.NINA_ATTACHMENTS_ENABLED = "YES";

  const failedIDs = iosArtifactChecks(artifact, validEnvironment(), facts)
    .filter((result) => result.status === "failure")
    .map((result) => result.id);

  assert(failedIDs.includes("artifact.attachment-release-decision"));
  assertFalse(failedIDs.includes("artifact.ai-release-decision"));
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

Deno.test("a verifier pinned to one App Store environment fails the gate, because App Review buys in sandbox", () => {
  for (const pinned of ["production", "sandbox", "xcode", "local_testing"]) {
    const environment = validEnvironment();
    environment.NINA_APP_STORE_ENVIRONMENT = pinned;

    const failedIDs = productionEnvironmentChecks(environment, facts)
      .filter((result) => result.status === "failure")
      .map((result) => result.id);

    assertEquals(failedIDs, ["environment.app-store-mode"], pinned);
  }

  const offline = validEnvironment();
  offline.NINA_APP_STORE_ONLINE_CHECKS = "false";
  assert(
    productionEnvironmentChecks(offline, facts).some((result) =>
      result.id === "environment.app-store-mode" &&
      result.status === "failure"
    ),
  );
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

Deno.test("a build that still carries the DEBUG test accounts fails the artifact check", () => {
  const artifact = validArtifact();
  artifact.containsDebugSignIn = true;

  const failedIDs = iosArtifactChecks(artifact, validEnvironment(), facts)
    .filter((result) => result.status === "failure")
    .map((result) => result.id);

  assertEquals(failedIDs, ["artifact.debug-sign-in"]);
  assert(containsDebugSignIn("Teste 1\0teste1@ninai.test\0"));
  assert(containsDebugSignIn("debug:test-two"));
  assertFalse(containsDebugSignIn("https://ninai.app/privacidade/"));
});

Deno.test("the shipped app signs in with Apple and calls no other sign-in door", async () => {
  const paths = [
    "../Nina/SupabaseAuthClient.swift",
    "../Nina/AuthSession.swift",
    "../Nina/LoginView.swift",
  ];
  const sources = await Promise.all(
    paths.map((path) => Deno.readTextFile(new URL(path, import.meta.url))),
  );

  for (const source of sources) {
    assertEquals(nonAppleSignInCalls(source), []);
  }
  assert(sources[0].includes("provider: .apple"));
});

Deno.test("the shipped app asks Apple for the name alone and never the email", async () => {
  const paths = [
    "../Nina/LoginView.swift",
    "../Nina/AuthSession.swift",
    "../Nina/SupabaseAuthClient.swift",
    "../Nina/ProfileStore.swift",
  ];
  const [login, session, client, profileStore] = await Promise.all(
    paths.map((path) => Deno.readTextFile(new URL(path, import.meta.url))),
  );

  for (const source of [login, session, client, profileStore]) {
    assertEquals(appleScopeRequests(source), []);
  }
  assert(asksAppleForTheNameAlone(login));
  assert(login.includes("request.requestedScopes = [.fullName]"));
  assert(session.includes("request.requestedScopes = []"));
  assert(profileStore.includes("sharedName?.givenName?"));
  for (const source of [login, session, client, profileStore]) {
    for (
      const part of [
        ".familyName",
        ".middleName",
        ".nickname",
        "PersonNameComponentsFormatter",
      ]
    ) {
      assertFalse(source.includes(part), part);
    }
  }
  assertFalse(client.includes("update_user_metadata"));
  assertFalse(client.includes("UserAttributes("));
  assertFalse(client.includes('"full_name": .string('));
  assertFalse(client.includes('"display_name": .string('));
});

Deno.test("Apple's given name reaches neither Auth nor the profile at sign-in", async () => {
  const client = await Deno.readTextFile(
    new URL("../Nina/SupabaseAuthClient.swift", import.meta.url),
  );

  assertFalse(client.includes("givenName"));
  assertFalse(client.includes("fullName"));
  assertEquals(
    [...client.matchAll(/ensureProfile\(displayNameHint: ([^)]*)\)/g)]
      .map((match) => match[1]),
    ["nil", "nil", "String?"],
  );
});

Deno.test("an email scope or any scope list but the name reads as asking Apple for data", () => {
  assertEquals(
    appleScopeRequests("request.requestedScopes = [.fullName, .email]"),
    ["requestedScopes = [.fullName, .email]"],
  );
  assertEquals(
    appleScopeRequests("request.requestedScopes = [.email]"),
    ["requestedScopes = [.email]"],
  );
  assertEquals(
    appleScopeRequests("request.requestedScopes = [.email, .fullName]"),
    ["requestedScopes = [.email, .fullName]"],
  );
  assertEquals(
    appleScopeRequests(
      "request.requestedScopes = Self.requestedScopes(for: reading)",
    ),
    ["requestedScopes = Self.requestedScopes(for: reading)"],
  );
  assertEquals(
    appleScopeRequests("request.requestedScopes?.append(.email)"),
    ["requestedScopes?.append(.email)"],
  );
  assertEquals(
    appleScopeRequests("request.requestedScopes! += [.email]"),
    ["requestedScopes! += [.email]"],
  );
  assertEquals(
    appleScopeRequests("request.requestedScopes += [.email]"),
    ["requestedScopes += [.email]"],
  );
  assertEquals(
    appleScopeRequests("let scope = ASAuthorization.Scope.email"),
    ["Scope.email"],
  );
  assertEquals(
    appleScopeRequests(
      "let scopes: [ASAuthorization.Scope] = [.fullName, .email]",
    ),
    ["[ASAuthorization.Scope] = [.fullName, .email]"],
  );
  assertEquals(appleScopeRequests("request.requestedScopes = [.fullName]"), []);
  assertEquals(
    appleScopeRequests("request.requestedScopes = [ .fullName ]"),
    [],
  );
  assertEquals(
    appleScopeRequests(
      "request.requestedScopes = [ASAuthorization.Scope.fullName]",
    ),
    [],
  );
  assertEquals(appleScopeRequests("request.requestedScopes = []"), []);
  assertEquals(appleScopeRequests("request.requestedScopes = [ ]"), []);
  assertEquals(appleScopeRequests("request.requestedScopes=[]"), []);
  assertEquals(appleScopeRequests('case .email: "Email"'), []);
  assertEquals(appleScopeRequests("provider: .email,"), []);

  assert(asksAppleForTheNameAlone("request.requestedScopes = [.fullName]"));
  assert(
    asksAppleForTheNameAlone(
      "request.requestedScopes = [ASAuthorization.Scope.fullName]",
    ),
  );
  assertFalse(asksAppleForTheNameAlone("request.requestedScopes = []"));
  assertFalse(asksAppleForTheNameAlone("let scopes = [.fullName]"));
  assertFalse(
    asksAppleForTheNameAlone("request.requestedScopes = [.fullName, .email]"),
  );
  assertFalse(
    asksAppleForTheNameAlone(
      "request.requestedScopes = [.fullName]\nrequest.requestedScopes = []",
    ),
  );
});

Deno.test("the app reads the server's fallback name as no name", async () => {
  const migrations = new URL("../supabase/migrations/", import.meta.url);
  const names: string[] = [];
  for await (const entry of Deno.readDir(migrations)) {
    if (entry.isFile && /^\d{12}_[a-z0-9_]+\.sql$/.test(entry.name)) {
      names.push(entry.name);
    }
  }
  names.sort();
  let definition = "";
  for (const name of names) {
    const sql = await Deno.readTextFile(new URL(name, migrations));
    const start = sql.indexOf(
      "create or replace function public.auth_user_display_name(",
    );
    if (start === -1) continue;
    const end = sql.indexOf("$$;", start);
    if (end === -1) continue;
    definition = sql.slice(start, end);
  }

  assert(definition.length > 0);
  assert(/'Família'\s*\);\s*$/.test(definition));

  const profileStore = await Deno.readTextFile(
    new URL("../Nina/ProfileStore.swift", import.meta.url),
  );
  assert(profileStore.includes('"família"'));
  assert(profileStore.includes('"você"'));
});

Deno.test("an email code, magic link, password, OAuth or non-Apple ID token reads as another door", () => {
  assertEquals(
    nonAppleSignInCalls(
      "try await client.auth.signInWithOTP(email: email, shouldCreateUser: false)",
    ),
    ["signInWithOTP"],
  );
  assertEquals(
    nonAppleSignInCalls(
      "try await client.auth.verifyOTP(email: e, token: t, type: .email)",
    ),
    ["verifyOTP"],
  );
  assertEquals(
    nonAppleSignInCalls(
      "try await client.auth.signInWithOAuth(provider: .google)",
    ),
    ["signInWithOAuth"],
  );
  assertEquals(
    nonAppleSignInCalls(
      "try await client.auth.update(user: UserAttributes(email: next))",
    ),
    ["UserAttributes(email"],
  );
  assertEquals(
    nonAppleSignInCalls(
      "OpenIDConnectCredentials(\n    provider: .google,\n    idToken: token\n)",
    ),
    ["OpenIDConnectCredentials"],
  );
  assertEquals(
    nonAppleSignInCalls(
      "OpenIDConnectCredentials(\n    provider: .apple,\n    idToken: token\n)",
    ),
    [],
  );
});

Deno.test("the shipped premium store finishes a purchase only after the server records it", async () => {
  const source = await Deno.readTextFile(
    new URL("../Nina/PremiumSubscriptionStore.swift", import.meta.url),
  );

  const finishes = premiumTransactionFinishes(source);

  assert(finishes.total >= 1);
  assertEquals(finishes.afterServerRecord, finishes.total);
});

Deno.test("a transaction finished outside the recorded-sale branch is counted as unguarded", () => {
  const unknownProductIsDiscarded = `
    guard productIDs.contains(transaction.productID) else {
        await transaction.finish()
        return
    }
    if didRecord {
        await transaction.finish()
    }
  `;

  assertEquals(
    premiumTransactionFinishes(unknownProductIsDiscarded),
    { total: 2, afterServerRecord: 1 },
  );
});

Deno.test("the shipped database gate pins one Supabase CLI version for CI and local runs", async () => {
  const [workflow, denoConfig] = await Promise.all([
    Deno.readTextFile(new URL("../.github/workflows/ci.yml", import.meta.url)),
    Deno.readTextFile(new URL("../deno.json", import.meta.url)),
  ]);

  const versions = pinnedSupabaseCLIVersions(workflow, denoConfig);

  assert(versions.continuousIntegration.length > 0);
  assert(versions.localTasks.length > 0);
  assertEquals(
    new Set([...versions.continuousIntegration, ...versions.localTasks]).size,
    1,
  );
});

Deno.test("a version pinned on only one side is not read as agreement", () => {
  const workflowOnly = pinnedSupabaseCLIVersions(
    "uses: supabase/setup-cli@v2\n        with:\n          version: 2.110.0\n",
    '{ "tasks": { "db:up": "npx --yes supabase start" } }',
  );

  assertEquals(workflowOnly, {
    continuousIntegration: ["2.110.0"],
    localTasks: [],
  });
});

Deno.test("an unrelated pinned version in CI is not mistaken for the database gate", () => {
  const versions = pinnedSupabaseCLIVersions(
    'uses: actions/setup-node@v6\n        with:\n          node-version: "22.12.0"\n',
    '{ "tasks": { "db:up": "npx --yes supabase@2.110.0 start" } }',
  );

  assertEquals(versions.continuousIntegration, []);
  assertEquals(versions.localTasks, ["2.110.0"]);
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

function productionAuthSettings(
  overrides: {
    external?: Record<string, boolean>;
    [key: string]: unknown;
  } = {},
): Record<string, unknown> {
  const { external, ...topLevel } = overrides;
  return {
    external: {
      anonymous_users: false,
      apple: true,
      azure: false,
      email: false,
      github: false,
      google: false,
      phone: false,
      ...external,
    },
    disable_signup: false,
    mailer_autoconfirm: false,
    phone_autoconfirm: false,
    sms_provider: "twilio",
    saml_enabled: false,
    passkeys_enabled: false,
    ...topLevel,
  };
}

Deno.test("the online sign-in check passes only when Apple is the one provider on", async () => {
  const environment = validEnvironment();
  const requests: string[] = [];
  const fetcher = (
    input: string | URL,
    init?: RequestInit,
  ): Promise<Response> => {
    const url = new URL(input);
    requests.push(url.href);
    assertEquals(url.host, "project-ref.supabase.co");
    assertEquals(url.pathname, "/auth/v1/settings");
    assertEquals(
      new Headers(init?.headers).get("apikey"),
      environment.NINA_SUPABASE_PUBLISHABLE_KEY,
    );
    return Promise.resolve(Response.json(productionAuthSettings()));
  };

  const result = await signInProviderCheck(environment, fetcher);

  assertEquals(result.id, "deployment.sign-in-providers");
  assertEquals(result.status, "pass");
  assertEquals(requests.length, 1);
  assertFalse(
    result.message.includes(environment.NINA_SUPABASE_PUBLISHABLE_KEY!),
  );
});

Deno.test("the online sign-in check fails closed while email, Google, passkeys or any other door is on, or the answer is unreadable", async () => {
  const answering = (body: unknown, status = 200) => (): Promise<Response> =>
    Promise.resolve(Response.json(body, { status }));
  const cases: Array<
    [string, (input: string | URL, init?: RequestInit) => Promise<Response>]
  > = [
    [
      "email on",
      answering(productionAuthSettings({ external: { email: true } })),
    ],
    [
      "google on",
      answering(productionAuthSettings({ external: { google: true } })),
    ],
    [
      "apple off",
      answering(productionAuthSettings({ external: { apple: false } })),
    ],
    [
      "phone on",
      answering(productionAuthSettings({ external: { phone: true } })),
    ],
    [
      "anonymous on",
      answering(
        productionAuthSettings({ external: { anonymous_users: true } }),
      ),
    ],
    [
      "passkeys on",
      answering(productionAuthSettings({ passkeys_enabled: true })),
    ],
    ["saml on", answering(productionAuthSettings({ saml_enabled: true }))],
    [
      "signup closed",
      answering(productionAuthSettings({ disable_signup: true })),
    ],
    ["status 500", answering(productionAuthSettings(), 500)],
    [
      "not json",
      () => Promise.resolve(new Response("<html>maintenance</html>")),
    ],
    ["no external block", answering({ disable_signup: false })],
    ["network failure", () => Promise.reject(new TypeError("offline"))],
  ];

  for (const [label, fetcher] of cases) {
    const result = await signInProviderCheck(validEnvironment(), fetcher);
    assertEquals(result.status, "failure", label);
  }

  const placeholder = validEnvironment();
  placeholder.NINA_SUPABASE_URL = "https://your-project-ref.supabase.co";
  let placeholderRequests = 0;
  const result = await signInProviderCheck(placeholder, () => {
    placeholderRequests += 1;
    return Promise.resolve(Response.json(productionAuthSettings()));
  });
  assertEquals(result.status, "failure");
  assertEquals(placeholderRequests, 0);

  assertFalse(isAppleOnlySignIn(undefined));
  assertFalse(isAppleOnlySignIn("apple"));
  assert(isAppleOnlySignIn(productionAuthSettings()));
});

Deno.test("the launch identity needs a company CNPJ, an address and an encarregado who is not the controller", () => {
  const failed = (environment: PreflightEnvironment) =>
    productionEnvironmentChecks(environment, facts).some((result) =>
      result.id === "deployment.legal-launch-identity" &&
      result.status === "failure"
    );

  assertFalse(failed(validEnvironment()));

  const individual = validEnvironment();
  individual.PUBLIC_NINA_LEGAL_ENTITY_NAME = "Heitor Castello";
  individual.PUBLIC_NINA_LEGAL_ENTITY_DOCUMENT = "123.456.789-09";
  individual.PUBLIC_NINA_DPO_NAME = "Heitor Castello";
  assert(failed(individual));

  const sameDPO = validEnvironment();
  sameDPO.PUBLIC_NINA_DPO_NAME = "NINA TECNOLOGIA LTDA";
  assert(failed(sameDPO));

  const noAddress = validEnvironment();
  noAddress.PUBLIC_NINA_LEGAL_ENTITY_ADDRESS =
    "replace_with_the_controller_address";
  assert(failed(noAddress));
  delete noAddress.PUBLIC_NINA_LEGAL_ENTITY_ADDRESS;
  assert(failed(noAddress));
});

Deno.test("the encarregado may not be a partner or administrator of the controller", () => {
  const failed = (environment: PreflightEnvironment) =>
    productionEnvironmentChecks(environment, facts).some((result) =>
      result.id === "deployment.legal-launch-identity" &&
      result.status === "failure"
    );

  const partnerDPO = validEnvironment();
  partnerDPO.NINA_CONTROLLER_DECISION_MAKERS = "Ana Souza, Heitor Castello";
  partnerDPO.PUBLIC_NINA_DPO_NAME = "HEITOR CASTELLO";
  assert(failed(partnerDPO));

  const unlisted = validEnvironment();
  delete unlisted.NINA_CONTROLLER_DECISION_MAKERS;
  assert(failed(unlisted));

  const placeholder = validEnvironment();
  placeholder.NINA_CONTROLLER_DECISION_MAKERS =
    "replace_with_the_partners_and_administrators";
  assert(failed(placeholder));

  const empty = validEnvironment();
  empty.NINA_CONTROLLER_DECISION_MAKERS = " , ";
  assert(failed(empty));

  const outsider = validEnvironment();
  outsider.NINA_CONTROLLER_DECISION_MAKERS = "Heitor Castello, Ana Souza";
  outsider.PUBLIC_NINA_DPO_NAME = "Beatriz Lima";
  assertFalse(failed(outsider));
});

Deno.test("App Attest must run in production mode in production", () => {
  for (
    const mode of [undefined, "development", "insecure-local", "Production"]
  ) {
    const environment = validEnvironment();
    if (mode === undefined) delete environment.NINA_APP_ATTEST_MODE;
    else environment.NINA_APP_ATTEST_MODE = mode;
    assert(
      productionEnvironmentChecks(environment, facts).some((result) =>
        result.id === "deployment.app-attest-mode" &&
        result.status === "failure"
      ),
      String(mode),
    );
  }
});

Deno.test("a build without the age entitlements or below iOS 26.4 fails the artifact checks", () => {
  const artifact = validArtifact();
  artifact.entitlements = {
    "com.apple.developer.devicecheck.appattest-environment": "development",
  };
  artifact.info.MinimumOSVersion = "26.3";

  const failedIDs = iosArtifactChecks(artifact, validEnvironment(), facts)
    .filter((result) => result.status === "failure")
    .map((result) => result.id);

  assertEquals(failedIDs.sort(), [
    "artifact.app-attest-environment-production",
    "artifact.declared-age-range-entitlement",
    "artifact.deployment-target-minimum",
  ]);

  const unreadable = validArtifact();
  delete unreadable.entitlements;
  assert(
    iosArtifactChecks(unreadable, validEnvironment(), facts).some((result) =>
      result.id === "artifact.declared-age-range-entitlement" &&
      result.status === "failure"
    ),
  );
});

Deno.test("a Swift or web string claiming nothing is kept fails the retention check", () => {
  assertEquals(
    retentionClaimOffenders([
      { path: "Nina/NinaChatView.swift", text: "A foto não fica guardada." },
      {
        path: "web/src/pages/index.astro",
        text: "O que ela lê, e por quanto tempo fica.",
      },
      { path: "docs/history.md", text: "servidor nenhum" },
    ]),
    [],
  );
  assertEquals(
    retentionClaimOffenders([
      {
        path: "Nina/NinaChatView.swift",
        text: "Nada do que você manda fica guardado lá.",
      },
      { path: "Nina/Sheets.swift", text: "usado só para responder" },
      {
        path: "web/src/pages/index.astro",
        text: "pede que não guarde o que recebe",
      },
      { path: "Nina/LoginView.swift", text: 'Text("Sua amiga Nina")' },
    ]),
    [
      "Nina/NinaChatView.swift: fica guardado lá",
      "Nina/Sheets.swift: usado só para responder",
      "web/src/pages/index.astro: não guarde o que recebe",
      "Nina/LoginView.swift: Sua amiga Nina",
    ],
  );
});

Deno.test("the Terms must state the rating and require no minimum age, and the families and report pages must exist", () => {
  const terms =
    "A classificação indicativa da Nina é {ninaRating.termsPhrase}.";
  assert(legalAgeRuleHolds({
    terms,
    familiesPageExists: true,
    reportPageExists: true,
  }));
  assertFalse(legalAgeRuleHolds({
    terms: `${terms} Você declara ter 18 anos ou mais.`,
    familiesPageExists: true,
    reportPageExists: true,
  }));
  assertFalse(legalAgeRuleHolds({
    terms: "Sem classificação.",
    familiesPageExists: true,
    reportPageExists: true,
  }));
  assertFalse(legalAgeRuleHolds({
    terms,
    familiesPageExists: false,
    reportPageExists: true,
  }));
  assertFalse(legalAgeRuleHolds({
    terms,
    familiesPageExists: true,
    reportPageExists: false,
  }));
});

Deno.test("the app and the website rating constants must agree", () => {
  const swift = 'enum NinaRating {\n    static let currentCode = "L"\n}';
  const web = 'export const ninaRatingCode: NinaRatingCode = "L";';
  assertEquals(ratingCodes(swift, web), { app: "L", web: "L" });
  assert(ratingConstantsAgree(swift, web));
  assertFalse(
    ratingConstantsAgree(
      swift,
      'export const ninaRatingCode: NinaRatingCode = "12";',
    ),
  );
  assertFalse(ratingConstantsAgree("", web));
  assertFalse(
    ratingConstantsAgree(
      'enum NinaRating {\n    static let currentCode = "X"\n}',
      'export const ninaRatingCode: NinaRatingCode = "X";',
    ),
  );
});

Deno.test("the rating mark is drawn on the welcome and the startup screen and nowhere else in the app", async () => {
  const shipped = await Promise.all(
    [
      "Nina/LoginView.swift",
      "Nina/AppRootView.swift",
      "Nina/Sheets.swift",
      "Nina/MinorViews.swift",
      "Nina/ChildDayView.swift",
      "Nina/NinaRating.swift",
    ].map(async (path) => ({
      path,
      text: await Deno.readTextFile(new URL(`../${path}`, import.meta.url)),
    })),
  );
  assertEquals(ratingMarkOffenders(shipped), []);

  const passing = [
    { path: "Nina/LoginView.swift", text: "ClassIndMark()" },
    { path: "Nina/AppRootView.swift", text: "ClassIndMark()" },
    { path: "Nina/NinaRating.swift", text: "struct ClassIndMark: View {}" },
    { path: "web/src/components/RatingMark.astro", text: "ClassIndMark(" },
  ];
  assertEquals(ratingMarkOffenders(passing), []);

  assertEquals(
    ratingMarkOffenders([
      ...passing,
      { path: "Nina/Sheets.swift", text: "ClassIndMark(size: 24)" },
    ]),
    ["Nina/Sheets.swift"],
  );
  assertEquals(
    ratingMarkOffenders([
      { path: "Nina/LoginView.swift", text: 'Text("Nina")' },
      { path: "Nina/AppRootView.swift", text: "ClassIndMark()" },
    ]),
    ["Nina/LoginView.swift (missing)"],
  );
});

Deno.test("both age-assurance entitlements must be declared with their release values", () => {
  const complete = `<dict>
\t<key>com.apple.developer.declared-age-range</key>
\t<true/>
\t<key>com.apple.developer.devicecheck.appattest-environment</key>
\t<string>production</string>
</dict>`;
  assert(ageAssuranceEntitlementsPresent(complete));
  assertFalse(
    ageAssuranceEntitlementsPresent(
      complete.replace(
        "<string>production</string>",
        "<string>development</string>",
      ),
    ),
  );
  assertFalse(
    ageAssuranceEntitlementsPresent(complete.replace("<true/>", "<false/>")),
  );
});

Deno.test("every deployment target must be 26.4 or later", () => {
  assert(deploymentTargetsAtLeast(
    "IPHONEOS_DEPLOYMENT_TARGET = 26.4;\nIPHONEOS_DEPLOYMENT_TARGET = 26.5;",
  ));
  assertFalse(deploymentTargetsAtLeast(
    "IPHONEOS_DEPLOYMENT_TARGET = 26.4;\nIPHONEOS_DEPLOYMENT_TARGET = 17.0;",
  ));
  assertFalse(deploymentTargetsAtLeast("no targets"));
  assert(versionAtLeast("27", "26.4"));
  assert(versionAtLeast("26.4.1", "26.4"));
  assertFalse(versionAtLeast("26.3.9", "26.4"));
  assertFalse(versionAtLeast("26.x", "26.4"));
});

Deno.test("a private-key header followed by a key body is a secret", () => {
  const body = "MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQg".repeat(2);
  assert(looksLikeSecret(`-----BEGIN PRIVATE KEY-----\n${body}\n`));
  assert(looksLikeSecret(`-----BEGIN EC PRIVATE KEY-----\n${body}`));
});

Deno.test("a private-key header around a key built at run time is not a secret", () => {
  const template =
    "privateKey: `-----BEGIN PRIVATE KEY-----\\n${body}\\n-----END PRIVATE KEY-----`,";
  assertFalse(looksLikeSecret(template));
});
