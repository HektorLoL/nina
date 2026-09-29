import { assert, assertEquals, assertFalse } from "@std/assert";
import {
  appleClientSecretLifetimeSeconds,
  appleRevokeEndpoint,
  appleSignInAudience,
  appleSignInClientID,
  appleSignInConfigurationFromEnvironment,
  appleTokenEndpoint,
  isAppleAuthorizationCode,
  normalizedPrivateKey,
  revokeAppleSignIn,
} from "./apple-sign-in-revocation.ts";

const teamID = "TEAMID0001";
const keyID = "KEYID00001";
const authorizationCode = "c1a2b3.0-_throwaway";
const fixedNow = new Date("2026-09-29T12:00:00Z");

type RecordedCall = {
  url: string;
  fields: Record<string, string>;
  hasTimeout: boolean;
};

// Each run signs with a key generated here and thrown away, so no real key
// ever appears in the repository, a fixture or a log.
async function throwawayKey(): Promise<
  { privateKey: string; publicKey: CryptoKey }
> {
  const pair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  ) as CryptoKeyPair;
  const der = new Uint8Array(
    await crypto.subtle.exportKey("pkcs8", pair.privateKey),
  );
  let binary = "";
  for (const byte of der) binary += String.fromCharCode(byte);
  const body = btoa(binary).match(/.{1,64}/g)!.join("\n");
  return {
    privateKey:
      `-----BEGIN PRIVATE KEY-----\n${body}\n-----END PRIVATE KEY-----`,
    publicKey: pair.publicKey,
  };
}

function decodeSegment(segment: string): Record<string, unknown> {
  const base64 = segment.replaceAll("-", "+").replaceAll("_", "/") +
    "=".repeat((4 - (segment.length % 4)) % 4);
  return JSON.parse(atob(base64));
}

function decodeBytes(segment: string): ArrayBuffer {
  const base64 = segment.replaceAll("-", "+").replaceAll("_", "/") +
    "=".repeat((4 - (segment.length % 4)) % 4);
  return Uint8Array.from(atob(base64), (character) => character.charCodeAt(0))
    .buffer as ArrayBuffer;
}

function recordingFetch(
  responses: Array<() => Response>,
): { fetch: typeof fetch; calls: RecordedCall[] } {
  const calls: RecordedCall[] = [];
  const fakeFetch: typeof fetch = (input, init) => {
    const body = typeof init?.body === "string" ? init.body : "";
    calls.push({
      url: String(input),
      fields: Object.fromEntries(new URLSearchParams(body)),
      hasTimeout: init?.signal instanceof AbortSignal,
    });
    const next = responses.shift();
    if (!next) return Promise.reject(new Error("unexpected call"));
    return Promise.resolve(next());
  };
  return { fetch: fakeFetch, calls };
}

Deno.test("revocation exchanges the code and revokes the refresh token with a signed client secret", async () => {
  const key = await throwawayKey();
  const { fetch, calls } = recordingFetch([
    () =>
      Response.json({
        access_token: "access-throwaway",
        refresh_token: "refresh-throwaway",
      }),
    () => new Response(null, { status: 200 }),
  ]);

  const result = await revokeAppleSignIn(authorizationCode, {
    configuration: { teamID, keyID, privateKey: key.privateKey },
    fetch,
    now: () => fixedNow,
  });

  assertEquals(result, { revoked: true });
  assertEquals(calls.map((call) => call.url), [
    appleTokenEndpoint,
    appleRevokeEndpoint,
  ]);
  assert(calls.every((call) => call.hasTimeout));
  assertEquals(calls[0].fields.client_id, appleSignInClientID);
  assertEquals(calls[0].fields.code, authorizationCode);
  assertEquals(calls[0].fields.grant_type, "authorization_code");
  assertEquals(calls[1].fields.token, "refresh-throwaway");
  assertEquals(calls[1].fields.token_type_hint, "refresh_token");
  assertEquals(calls[1].fields.client_secret, calls[0].fields.client_secret);

  const [header, claims, signature] = calls[0].fields.client_secret.split(".");
  assertEquals(decodeSegment(header), { alg: "ES256", kid: keyID });
  const issuedAt = Math.floor(fixedNow.getTime() / 1_000);
  assertEquals(decodeSegment(claims), {
    iss: teamID,
    iat: issuedAt,
    exp: issuedAt + appleClientSecretLifetimeSeconds,
    aud: appleSignInAudience,
    sub: appleSignInClientID,
  });
  assert(
    await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      key.publicKey,
      decodeBytes(signature),
      new TextEncoder().encode(`${header}.${claims}`),
    ),
  );
});

Deno.test("revocation falls back to the access token when Apple returns no refresh token", async () => {
  const key = await throwawayKey();
  const { fetch, calls } = recordingFetch([
    () => Response.json({ access_token: "access-throwaway" }),
    () => new Response(null, { status: 200 }),
  ]);

  const result = await revokeAppleSignIn(authorizationCode, {
    configuration: { teamID, keyID, privateKey: key.privateKey },
    fetch,
  });

  assertEquals(result, { revoked: true });
  assertEquals(calls[1].fields.token, "access-throwaway");
  assertEquals(calls[1].fields.token_type_hint, "access_token");
});

Deno.test("a key whose line breaks arrived escaped still signs", async () => {
  const key = await throwawayKey();
  const escaped = key.privateKey.replaceAll("\n", "\\n");
  assertEquals(normalizedPrivateKey(escaped), key.privateKey);

  const { fetch } = recordingFetch([
    () => Response.json({ refresh_token: "refresh-throwaway" }),
    () => new Response(null, { status: 200 }),
  ]);
  const result = await revokeAppleSignIn(authorizationCode, {
    configuration: { teamID, keyID, privateKey: escaped },
    fetch,
  });
  assertEquals(result, { revoked: true });
});

Deno.test("missing or malformed configuration skips revocation without calling Apple", async () => {
  const key = await throwawayKey();
  const configurations = [
    undefined,
    { teamID, keyID },
    { teamID: "short", keyID, privateKey: key.privateKey },
    { teamID, keyID: "lowercase1", privateKey: key.privateKey },
    { teamID, keyID, privateKey: "not a key" },
  ];

  for (const configuration of configurations) {
    const { fetch, calls } = recordingFetch([]);
    const result = await revokeAppleSignIn(authorizationCode, {
      configuration,
      fetch,
    });
    assertEquals(result, { revoked: false, stage: "configuration" });
    assertEquals(calls, []);
  }
});

Deno.test("a refused code exchange stops before any revoke call", async () => {
  const key = await throwawayKey();
  for (
    const response of [
      () => new Response("{}", { status: 400 }),
      () => Response.json({}),
    ]
  ) {
    const { fetch, calls } = recordingFetch([response]);
    const result = await revokeAppleSignIn(authorizationCode, {
      configuration: { teamID, keyID, privateKey: key.privateKey },
      fetch,
    });
    assertEquals(result, { revoked: false, stage: "token_exchange" });
    assertEquals(calls.length, 1);
  }

  const { fetch, calls } = recordingFetch([]);
  const malformed = await revokeAppleSignIn("code with spaces", {
    configuration: { teamID, keyID, privateKey: key.privateKey },
    fetch,
  });
  assertEquals(malformed, { revoked: false, stage: "token_exchange" });
  assertEquals(calls, []);
});

Deno.test("a failed revoke reports its stage and never throws", async () => {
  const key = await throwawayKey();
  const { fetch } = recordingFetch([
    () => Response.json({ refresh_token: "refresh-throwaway" }),
    () => new Response(null, { status: 503 }),
  ]);
  const refused = await revokeAppleSignIn(authorizationCode, {
    configuration: { teamID, keyID, privateKey: key.privateKey },
    fetch,
  });
  assertEquals(refused, { revoked: false, stage: "revoke" });

  const unreachable = await revokeAppleSignIn(authorizationCode, {
    configuration: { teamID, keyID, privateKey: key.privateKey },
    fetch: () => Promise.reject(new TypeError("network")),
  });
  assertEquals(unreachable, { revoked: false, stage: "token_exchange" });
});

Deno.test("the configuration is read from the three Edge Function secrets and nothing else", () => {
  const read = (name: string) =>
    ({
      APPLE_SIGN_IN_TEAM_ID: ` ${teamID} `,
      APPLE_SIGN_IN_KEY_ID: keyID,
      APPLE_SIGN_IN_PRIVATE_KEY: "placeholder",
    })[name];
  assertEquals(appleSignInConfigurationFromEnvironment(read), {
    teamID,
    keyID,
    privateKey: "placeholder",
  });
  assert(isAppleAuthorizationCode(authorizationCode));
  assertFalse(isAppleAuthorizationCode(""));
  assertFalse(isAppleAuthorizationCode("a".repeat(513)));
  assertFalse(isAppleAuthorizationCode("code/with/slashes"));
});

Deno.test("the revocation module never logs and never reaches a key file", async () => {
  const source = await Deno.readTextFile(
    new URL("./apple-sign-in-revocation.ts", import.meta.url),
  );
  assertFalse(source.includes("console."));
  assertFalse(source.includes(".p8"));
  assertFalse(source.includes("Deno.readFile"));
  assertFalse(source.includes("Deno.readTextFile"));
  assertFalse(source.includes("npm:"));
});
