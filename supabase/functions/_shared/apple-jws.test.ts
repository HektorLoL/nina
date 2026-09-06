import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import * as x509 from "npm:@peculiar/x509@1.14.3";
import {
  AppleEnvironment,
  AppleVerificationError,
  type AppleVerifierConfiguration,
  verifyAppleCertificateChain,
  verifyAppleJWS,
  verifyAppleNotification,
  verifyAppleTransaction,
} from "./apple-jws.ts";

// Apple's published production chain, as shipped in the App Store Server Library's
// own test suite. Public data; the leaf expires in October 2027.
const appleRoot =
  "MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA==";
const appleIntermediate =
  "MIIDFjCCApygAwIBAgIUIsGhRwp0c2nvU4YSycafPTjzbNcwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMjEwMzE3MjAzNzEwWhcNMzYwMzE5MDAwMDAwWjB1MUQwQgYDVQQDDDtBcHBsZSBXb3JsZHdpZGUgRGV2ZWxvcGVyIFJlbGF0aW9ucyBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTELMAkGA1UECwwCRzYxEzARBgNVBAoMCkFwcGxlIEluYy4xCzAJBgNVBAYTAlVTMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAEbsQKC94PrlWmZXnXgtxzdVJL8T0SGYngDRGpngn3N6PT8JMEb7FDi4bBmPhCnZ3/sq6PF/cGcKXWsL5vOteRhyJ45x3ASP7cOB+aao90fcpxSv/EZFbniAbNgZGhIhpIo4H6MIH3MBIGA1UdEwEB/wQIMAYBAf8CAQAwHwYDVR0jBBgwFoAUu7DeoVgziJqkipnevr3rr9rLJKswRgYIKwYBBQUHAQEEOjA4MDYGCCsGAQUFBzABhipodHRwOi8vb2NzcC5hcHBsZS5jb20vb2NzcDAzLWFwcGxlcm9vdGNhZzMwNwYDVR0fBDAwLjAsoCqgKIYmaHR0cDovL2NybC5hcHBsZS5jb20vYXBwbGVyb290Y2FnMy5jcmwwHQYDVR0OBBYEFD8vlCNR01DJmig97bB85c+lkGKZMA4GA1UdDwEB/wQEAwIBBjAQBgoqhkiG92NkBgIBBAIFADAKBggqhkjOPQQDAwNoADBlAjBAXhSq5IyKogMCPtw490BaB677CaEGJXufQB/EqZGd6CSjiCtOnuMTbXVXmxxcxfkCMQDTSPxarZXvNrkxU3TkUMI33yzvFVVRT4wxWJC994OsdcZ4+RGNsYDyR5gmdr0nDGg=";
const appleLeaf =
  "MIIEMTCCA7agAwIBAgIQR8KHzdn554Z/UoradNx9tzAKBggqhkjOPQQDAzB1MUQwQgYDVQQDDDtBcHBsZSBXb3JsZHdpZGUgRGV2ZWxvcGVyIFJlbGF0aW9ucyBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTELMAkGA1UECwwCRzYxEzARBgNVBAoMCkFwcGxlIEluYy4xCzAJBgNVBAYTAlVTMB4XDTI1MDkxOTE5NDQ1MVoXDTI3MTAxMzE3NDcyM1owgZIxQDA+BgNVBAMMN1Byb2QgRUNDIE1hYyBBcHAgU3RvcmUgYW5kIGlUdW5lcyBTdG9yZSBSZWNlaXB0IFNpZ25pbmcxLDAqBgNVBAsMI0FwcGxlIFdvcmxkd2lkZSBEZXZlbG9wZXIgUmVsYXRpb25zMRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABNnVvhcv7iT+7Ex5tBMBgrQspHzIsXRi0Yxfek7lv8wEmj/bHiWtNwJqc2BoHzsQiEjP7KFIIKg4Y8y0/nynuAmjggIIMIICBDAMBgNVHRMBAf8EAjAAMB8GA1UdIwQYMBaAFD8vlCNR01DJmig97bB85c+lkGKZMHAGCCsGAQUFBwEBBGQwYjAtBggrBgEFBQcwAoYhaHR0cDovL2NlcnRzLmFwcGxlLmNvbS93d2RyZzYuZGVyMDEGCCsGAQUFBzABhiVodHRwOi8vb2NzcC5hcHBsZS5jb20vb2NzcDAzLXd3ZHJnNjAyMIIBHgYDVR0gBIIBFTCCAREwggENBgoqhkiG92NkBQYBMIH+MIHDBggrBgEFBQcCAjCBtgyBs1JlbGlhbmNlIG9uIHRoaXMgY2VydGlmaWNhdGUgYnkgYW55IHBhcnR5IGFzc3VtZXMgYWNjZXB0YW5jZSBvZiB0aGUgdGhlbiBhcHBsaWNhYmxlIHN0YW5kYXJkIHRlcm1zIGFuZCBjb25kaXRpb25zIG9mIHVzZSwgY2VydGlmaWNhdGUgcG9saWN5IGFuZCBjZXJ0aWZpY2F0aW9uIHByYWN0aWNlIHN0YXRlbWVudHMuMDYGCCsGAQUFBwIBFipodHRwOi8vd3d3LmFwcGxlLmNvbS9jZXJ0aWZpY2F0ZWF1dGhvcml0eS8wHQYDVR0OBBYEFIFioG4wMMVA1ku9zJmGNPAVn3eqMA4GA1UdDwEB/wQEAwIHgDAQBgoqhkiG92NkBgsBBAIFADAKBggqhkjOPQQDAwNpADBmAjEA+qXnREC7hXIWVLsLxznjRpIzPf7VHz9V/CTm8+LJlrQepnmcPvGLNcX6XPnlcgLAAjEA5IjNZKgg5pQ79knF4IbTXdKv8vutIDMXDmjPVT3dGvFtsGRwXOywR2kZCdSrfeot";

const signing = {
  name: "ECDSA",
  namedCurve: "P-256",
  hash: "SHA-256",
} as const;
const derNull = new Uint8Array([0x05, 0x00]);
const leafMarker = "1.2.840.113635.100.6.11.1";
const intermediateMarker = "1.2.840.113635.100.6.2.1";

interface TestAuthority {
  root: x509.X509Certificate;
  intermediate: x509.X509Certificate;
  leaf: x509.X509Certificate;
  leafKeys: CryptoKeyPair;
}

async function makeAuthority(
  options: {
    leafMarker?: boolean;
    intermediateMarker?: boolean;
    intermediateIsCA?: boolean;
    leafNotAfter?: Date;
  } = {},
): Promise<TestAuthority> {
  const notBefore = new Date("2026-01-01T00:00:00Z");
  const notAfter = new Date("2036-01-01T00:00:00Z");
  const rootKeys = await crypto.subtle.generateKey(signing, true, [
    "sign",
    "verify",
  ]);
  const root = await x509.X509CertificateGenerator.createSelfSigned({
    serialNumber: "01",
    name: "CN=Test Root, O=Nina Tests",
    notBefore,
    notAfter,
    signingAlgorithm: signing,
    keys: rootKeys,
    extensions: [new x509.BasicConstraintsExtension(true, 2, true)],
  });
  const intermediateKeys = await crypto.subtle.generateKey(signing, true, [
    "sign",
    "verify",
  ]);
  const intermediateExtensions: x509.Extension[] = [
    new x509.BasicConstraintsExtension(
      options.intermediateIsCA ?? true,
      1,
      true,
    ),
  ];
  if (options.intermediateMarker ?? true) {
    intermediateExtensions.push(
      new x509.Extension(intermediateMarker, false, derNull),
    );
  }
  const intermediate = await x509.X509CertificateGenerator.create({
    serialNumber: "02",
    subject: "CN=Test Intermediate, O=Nina Tests",
    issuer: root.subject,
    notBefore,
    notAfter,
    signingAlgorithm: signing,
    publicKey: intermediateKeys.publicKey,
    signingKey: rootKeys.privateKey,
    extensions: intermediateExtensions,
  });
  const leafKeys = await crypto.subtle.generateKey(signing, true, [
    "sign",
    "verify",
  ]);
  const leafExtensions: x509.Extension[] = [
    new x509.BasicConstraintsExtension(false),
  ];
  if (options.leafMarker ?? true) {
    leafExtensions.push(new x509.Extension(leafMarker, false, derNull));
  }
  const leaf = await x509.X509CertificateGenerator.create({
    serialNumber: "03",
    subject: "CN=Test Receipt Signing, O=Nina Tests",
    issuer: intermediate.subject,
    notBefore,
    notAfter: options.leafNotAfter ?? notAfter,
    signingAlgorithm: signing,
    publicKey: leafKeys.publicKey,
    signingKey: intermediateKeys.privateKey,
    extensions: leafExtensions,
  });
  return { root, intermediate, leaf, leafKeys };
}

function base64URL(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(
    /\//g,
    "_",
  ).replace(/=+$/, "");
}

function base64(certificate: x509.X509Certificate): string {
  return btoa(String.fromCharCode(...new Uint8Array(certificate.rawData)));
}

async function sign(
  authority: TestAuthority,
  payload: Record<string, unknown>,
  chain: string[] = [
    base64(authority.leaf),
    base64(authority.intermediate),
    base64(authority.root),
  ],
  alg = "ES256",
): Promise<string> {
  const header = base64URL(
    new TextEncoder().encode(JSON.stringify({ alg, x5c: chain })),
  );
  const body = base64URL(new TextEncoder().encode(JSON.stringify(payload)));
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    authority.leafKeys.privateKey,
    new TextEncoder().encode(`${header}.${body}`),
  );
  return `${header}.${body}.${base64URL(new Uint8Array(signature))}`;
}

function configuration(
  authority: TestAuthority,
  overrides: Partial<AppleVerifierConfiguration> = {},
): AppleVerifierConfiguration {
  return {
    rootCertificates: [new Uint8Array(authority.root.rawData)],
    environment: AppleEnvironment.SANDBOX,
    bundleID: "com.heitor.nina",
    useCurrentDate: true,
    ...overrides,
  };
}

const sandboxTransaction = {
  transactionId: "2000000999999999",
  originalTransactionId: "2000000999999999",
  bundleId: "com.heitor.nina",
  productId: "com.heitor.nina.premium.monthly",
  environment: "Sandbox",
  type: "Auto-Renewable Subscription",
  signedDate: Date.parse("2026-09-06T20:00:00Z"),
};

async function status(promise: Promise<unknown>): Promise<string> {
  try {
    await promise;
    return "ok";
  } catch (error) {
    return error instanceof AppleVerificationError
      ? error.status
      : "unexpected";
  }
}

Deno.test("a receipt signed by a marked leaf under a marked CA verifies", async () => {
  const authority = await makeAuthority();
  const payload = await verifyAppleTransaction<{ transactionId: string }>(
    await sign(authority, sandboxTransaction),
    configuration(authority),
  );
  assertEquals(payload.transactionId, "2000000999999999");
});

Deno.test("a tampered payload, a foreign key, or a bad algorithm is refused", async () => {
  const authority = await makeAuthority();
  const jws = await sign(authority, sandboxTransaction);
  const [header, , signature] = jws.split(".");
  const tamperedBody = base64URL(
    new TextEncoder().encode(
      JSON.stringify({
        ...sandboxTransaction,
        productId: "com.heitor.nina.premium.yearly",
      }),
    ),
  );
  assertEquals(
    await status(
      verifyAppleJWS(
        `${header}.${tamperedBody}.${signature}`,
        configuration(authority),
      ),
    ),
    "verification_failure",
  );

  const stranger = await makeAuthority();
  assertEquals(
    await status(
      verifyAppleJWS(
        await sign(stranger, sandboxTransaction),
        configuration(authority),
      ),
    ),
    "verification_failure",
  );
  assertEquals(
    await status(
      verifyAppleJWS(
        await sign(authority, sandboxTransaction, undefined, "HS256"),
        configuration(authority),
      ),
    ),
    "verification_failure",
  );
});

Deno.test("the chain must be exactly three certificates rooted in a trusted root", async () => {
  const authority = await makeAuthority();
  assertEquals(
    await status(
      verifyAppleJWS(
        await sign(authority, sandboxTransaction, [
          base64(authority.leaf),
          base64(authority.intermediate),
        ]),
        configuration(authority),
      ),
    ),
    "invalid_chain_length",
  );
  assertEquals(
    await status(
      verifyAppleJWS(
        await sign(authority, sandboxTransaction),
        configuration(authority, { rootCertificates: [] }),
      ),
    ),
    "verification_failure",
  );
  assertEquals(
    await status(
      verifyAppleJWS(
        await sign(
          authority,
          sandboxTransaction,
          [
            "not-a-certificate",
            base64(authority.intermediate),
            base64(authority.root),
          ],
        ),
        configuration(authority),
      ),
    ),
    "invalid_certificate",
  );
});

Deno.test("Apple's marker extensions and the CA flag are required", async () => {
  const noLeafMarker = await makeAuthority({ leafMarker: false });
  assertEquals(
    await status(
      verifyAppleJWS(
        await sign(noLeafMarker, sandboxTransaction),
        configuration(noLeafMarker),
      ),
    ),
    "verification_failure",
  );
  const noIntermediateMarker = await makeAuthority({
    intermediateMarker: false,
  });
  assertEquals(
    await status(
      verifyAppleJWS(
        await sign(noIntermediateMarker, sandboxTransaction),
        configuration(noIntermediateMarker),
      ),
    ),
    "verification_failure",
  );
  const notCA = await makeAuthority({ intermediateIsCA: false });
  assertEquals(
    await status(
      verifyAppleJWS(
        await sign(notCA, sandboxTransaction),
        configuration(notCA),
      ),
    ),
    "verification_failure",
  );
});

Deno.test("validity is checked against the clock, or against the signing date when asked", async () => {
  const expired = await makeAuthority({
    leafNotAfter: new Date("2026-06-01T00:00:00Z"),
  });
  const signedWhileValid = {
    ...sandboxTransaction,
    signedDate: Date.parse("2026-03-01T00:00:00Z"),
  };
  assertEquals(
    await status(
      verifyAppleJWS(
        await sign(expired, signedWhileValid),
        configuration(expired, { useCurrentDate: true }),
      ),
    ),
    "verification_failure",
  );
  assertEquals(
    await status(
      verifyAppleJWS(
        await sign(expired, signedWhileValid),
        configuration(expired, { useCurrentDate: false }),
      ),
    ),
    "ok",
  );
});

Deno.test("a transaction must name this app and the configured environment", async () => {
  const authority = await makeAuthority();
  assertEquals(
    await status(
      verifyAppleTransaction(
        await sign(authority, {
          ...sandboxTransaction,
          bundleId: "com.example.other",
        }),
        configuration(authority),
      ),
    ),
    "invalid_app_identifier",
  );
  assertEquals(
    await status(
      verifyAppleTransaction(
        await sign(authority, sandboxTransaction),
        configuration(authority, {
          environment: AppleEnvironment.PRODUCTION,
          appAppleID: 6808423946,
        }),
      ),
    ),
    "invalid_environment",
  );
});

Deno.test("a notification is checked through whichever body Apple used", async () => {
  const authority = await makeAuthority();
  const data = {
    bundleId: "com.heitor.nina",
    environment: "Sandbox",
    appAppleId: 6808423946,
  };
  assertEquals(
    await status(
      verifyAppleNotification(
        await sign(authority, { notificationType: "TEST", data }),
        configuration(authority),
      ),
    ),
    "ok",
  );
  assertEquals(
    await status(
      verifyAppleNotification(
        await sign(authority, { notificationType: "TEST", summary: data }),
        configuration(authority),
      ),
    ),
    "ok",
  );
  assertEquals(
    await status(
      verifyAppleNotification(
        await sign(authority, {
          notificationType: "TEST",
          data: { ...data, bundleId: "com.example.other" },
        }),
        configuration(authority),
      ),
    ),
    "invalid_app_identifier",
  );
  assertEquals(
    await status(
      verifyAppleNotification(
        await sign(authority, {
          notificationType: "TEST",
          data: { ...data, environment: "Production" },
        }),
        configuration(authority),
      ),
    ),
    "invalid_environment",
  );
  const production = configuration(authority, {
    environment: AppleEnvironment.PRODUCTION,
    appAppleID: 6808423946,
  });
  const productionData = { ...data, environment: "Production" };
  assertEquals(
    await status(
      verifyAppleNotification(
        await sign(authority, {
          notificationType: "TEST",
          data: productionData,
        }),
        production,
      ),
    ),
    "ok",
  );
  assertEquals(
    await status(
      verifyAppleNotification(
        await sign(authority, {
          notificationType: "TEST",
          data: { ...productionData, appAppleId: 1 },
        }),
        production,
      ),
    ),
    "invalid_app_identifier",
  );
});

Deno.test("Xcode and local testing payloads are decoded without a signature, when explicitly configured", async () => {
  const authority = await makeAuthority();
  const header = base64URL(
    new TextEncoder().encode(JSON.stringify({ alg: "ES256" })),
  );
  const body = base64URL(
    new TextEncoder().encode(
      JSON.stringify({ ...sandboxTransaction, environment: "Xcode" }),
    ),
  );
  const payload = await verifyAppleTransaction<{ environment: string }>(
    `${header}.${body}.c2ln`,
    configuration(authority, { environment: AppleEnvironment.XCODE }),
  );
  assertEquals(payload.environment, "Xcode");
});

Deno.test("Apple's real production chain passes the chain rules", async () => {
  const leaf = new x509.X509Certificate(appleLeaf);
  const intermediate = new x509.X509Certificate(appleIntermediate);
  const root = Uint8Array.from(
    atob(appleRoot),
    (character) => character.charCodeAt(0),
  );
  const key = await verifyAppleCertificateChain(
    [root],
    leaf,
    intermediate,
    new Date("2026-09-06T00:00:00Z"),
  );
  assert(key instanceof CryptoKey);
  await assertRejects(
    () =>
      verifyAppleCertificateChain(
        [root],
        leaf,
        intermediate,
        new Date("2030-01-01T00:00:00Z"),
      ),
    AppleVerificationError,
    "verification_failure",
  );
});
