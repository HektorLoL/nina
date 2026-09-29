export const appleSignInClientID = "com.heitor.nina";
export const appleSignInAudience = "https://appleid.apple.com";
export const appleTokenEndpoint = "https://appleid.apple.com/auth/token";
export const appleRevokeEndpoint = "https://appleid.apple.com/auth/revoke";
export const appleRevocationTimeoutMilliseconds = 8_000;
export const appleClientSecretLifetimeSeconds = 300;

const appleIdentifierPattern = /^[A-Z0-9]{10}$/;
const authorizationCodePattern = /^[A-Za-z0-9._-]{1,512}$/;
const pemBoundaryPattern = /-----[A-Z ]+-----/g;

export type AppleRevocationStage =
  | "configuration"
  | "token_exchange"
  | "revoke";

export type AppleRevocationResult =
  | { revoked: true }
  | { revoked: false; stage: AppleRevocationStage };

export type AppleSignInConfiguration = {
  teamID: string;
  keyID: string;
  privateKey: string;
};

export type AppleRevocationDependencies = {
  configuration?: Partial<AppleSignInConfiguration>;
  fetch?: typeof fetch;
  now?: () => Date;
};

export function isAppleAuthorizationCode(value: unknown): value is string {
  return typeof value === "string" && authorizationCodePattern.test(value);
}

export function appleSignInConfigurationFromEnvironment(
  read: (name: string) => string | undefined,
): Partial<AppleSignInConfiguration> {
  return {
    teamID: read("APPLE_SIGN_IN_TEAM_ID")?.trim(),
    keyID: read("APPLE_SIGN_IN_KEY_ID")?.trim(),
    privateKey: read("APPLE_SIGN_IN_PRIVATE_KEY"),
  };
}

// A literal \n in a stored key is a line break, never key material.
export function normalizedPrivateKey(value: string): string {
  return value.replaceAll("\\n", "\n").trim();
}

function base64URL(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(
    /=+$/,
    "",
  );
}

function base64URLText(value: unknown): string {
  return base64URL(new TextEncoder().encode(JSON.stringify(value)));
}

function pkcs8Bytes(privateKey: string): Uint8Array | null {
  const body = normalizedPrivateKey(privateKey)
    .replace(pemBoundaryPattern, "")
    .replace(/\s+/g, "");
  if (!body || !/^[A-Za-z0-9+/]+=*$/.test(body)) return null;
  try {
    return Uint8Array.from(atob(body), (character) => character.charCodeAt(0));
  } catch {
    return null;
  }
}

async function importSigningKey(privateKey: string): Promise<CryptoKey | null> {
  const der = pkcs8Bytes(privateKey);
  if (!der) return null;
  try {
    return await crypto.subtle.importKey(
      "pkcs8",
      der.buffer.slice(
        der.byteOffset,
        der.byteOffset + der.byteLength,
      ) as ArrayBuffer,
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["sign"],
    );
  } catch {
    return null;
  }
}

function validConfiguration(
  configuration: Partial<AppleSignInConfiguration> | undefined,
): AppleSignInConfiguration | null {
  const teamID = configuration?.teamID ?? "";
  const keyID = configuration?.keyID ?? "";
  const privateKey = configuration?.privateKey ?? "";
  if (
    !appleIdentifierPattern.test(teamID) ||
    !appleIdentifierPattern.test(keyID) ||
    !privateKey.trim()
  ) {
    return null;
  }
  return { teamID, keyID, privateKey };
}

export async function appleClientSecret(
  configuration: AppleSignInConfiguration,
  signingKey: CryptoKey,
  now: Date,
): Promise<string> {
  const issuedAt = Math.floor(now.getTime() / 1_000);
  const signingInput = `${
    base64URLText({ alg: "ES256", kid: configuration.keyID })
  }.${
    base64URLText({
      iss: configuration.teamID,
      iat: issuedAt,
      exp: issuedAt + appleClientSecretLifetimeSeconds,
      aud: appleSignInAudience,
      sub: appleSignInClientID,
    })
  }`;
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    signingKey,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64URL(new Uint8Array(signature))}`;
}

async function postForm(
  fetcher: typeof fetch,
  url: string,
  fields: Record<string, string>,
): Promise<Response> {
  return await fetcher(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Accept: "application/json",
    },
    body: new URLSearchParams(fields).toString(),
    redirect: "error",
    signal: AbortSignal.timeout(appleRevocationTimeoutMilliseconds),
  });
}

// Revocation is best effort and never throws: the account it belongs to has
// already been deleted, so a failure can only be reported, not undone.
export async function revokeAppleSignIn(
  authorizationCode: string,
  dependencies: AppleRevocationDependencies,
): Promise<AppleRevocationResult> {
  const configuration = validConfiguration(dependencies.configuration);
  if (!configuration) return { revoked: false, stage: "configuration" };

  const signingKey = await importSigningKey(configuration.privateKey);
  if (!signingKey) return { revoked: false, stage: "configuration" };

  if (!isAppleAuthorizationCode(authorizationCode)) {
    return { revoked: false, stage: "token_exchange" };
  }

  const fetcher = dependencies.fetch ?? fetch;
  let clientSecret: string;
  try {
    clientSecret = await appleClientSecret(
      configuration,
      signingKey,
      dependencies.now?.() ?? new Date(),
    );
  } catch {
    return { revoked: false, stage: "configuration" };
  }

  let token: string;
  let tokenTypeHint: "refresh_token" | "access_token";
  try {
    const response = await postForm(fetcher, appleTokenEndpoint, {
      client_id: appleSignInClientID,
      client_secret: clientSecret,
      code: authorizationCode,
      grant_type: "authorization_code",
    });
    if (!response.ok) {
      await response.body?.cancel().catch(() => undefined);
      return { revoked: false, stage: "token_exchange" };
    }
    const payload = await response.json() as Record<string, unknown>;
    if (
      typeof payload.refresh_token === "string" && payload.refresh_token
    ) {
      token = payload.refresh_token;
      tokenTypeHint = "refresh_token";
    } else if (
      typeof payload.access_token === "string" && payload.access_token
    ) {
      token = payload.access_token;
      tokenTypeHint = "access_token";
    } else {
      return { revoked: false, stage: "token_exchange" };
    }
  } catch {
    return { revoked: false, stage: "token_exchange" };
  }

  try {
    const response = await postForm(fetcher, appleRevokeEndpoint, {
      client_id: appleSignInClientID,
      client_secret: clientSecret,
      token,
      token_type_hint: tokenTypeHint,
    });
    await response.body?.cancel().catch(() => undefined);
    return response.status === 200
      ? { revoked: true }
      : { revoked: false, stage: "revoke" };
  } catch {
    return { revoked: false, stage: "revoke" };
  }
}
