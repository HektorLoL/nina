import { assert, assertEquals, assertFalse, assertRejects } from "@std/assert";
// deno-lint-ignore no-import-prefix
import * as x509 from "npm:@peculiar/x509@1.14.3";
import type { MappedAge } from "./age-assurance.ts";
import {
  type AgeSignalBackend,
  AgeSignalRejected,
  appAttestAppID,
  AppAttestError,
  appAttestNonceOID,
  appleAppAttestRootPEM,
  assertionClientDataHash,
  encodeBase64,
  handleAgeSignalRequest,
  registrationClientDataHash,
  resolveAppAttestMode,
  rootCertificatesFrom,
  sha256,
  type StoredAttestKey,
  verifyAssertion,
  verifyAttestation,
} from "./app-attest.ts";

const userID = "10000000-0000-4000-9000-00000000000a";
const now = new Date();
const signing = {
  name: "ECDSA",
  namedCurve: "P-256",
  hash: "SHA-256",
} as const;

function bytes(
  ...parts: Array<Uint8Array | number[]>
): Uint8Array<ArrayBuffer> {
  const flattened = parts.flatMap((part) => [...part]);
  return new Uint8Array(flattened);
}

function cborHead(major: number, length: number): number[] {
  if (length < 24) return [(major << 5) | length];
  if (length < 256) return [(major << 5) | 24, length];
  return [(major << 5) | 25, length >> 8, length & 0xff];
}

type Encodable =
  | string
  | number
  | Uint8Array
  | Encodable[]
  | Map<string, Encodable>;

function cbor(value: Encodable): Uint8Array {
  if (typeof value === "number") return bytes(cborHead(0, value));
  if (typeof value === "string") {
    const encoded = new TextEncoder().encode(value);
    return bytes(cborHead(3, encoded.byteLength), encoded);
  }
  if (value instanceof Uint8Array) {
    return bytes(cborHead(2, value.byteLength), value);
  }
  if (Array.isArray(value)) {
    return bytes(cborHead(4, value.length), ...value.map(cbor));
  }
  const entries = [...value.entries()];
  return bytes(
    cborHead(5, entries.length),
    ...entries.flatMap(([key, item]) => [cbor(key), cbor(item)]),
  );
}

function rawToDER(raw: Uint8Array): Uint8Array {
  const integer = (component: Uint8Array) => {
    let start = 0;
    while (start < component.length - 1 && component[start] === 0) start += 1;
    let value: Uint8Array = component.slice(start);
    if (value[0] & 0x80) value = bytes([0], value);
    return bytes([0x02, value.length], value);
  };
  const body = bytes(integer(raw.slice(0, 32)), integer(raw.slice(32)));
  return bytes([0x30, body.length], body);
}

type TestDevice = {
  root: x509.X509Certificate;
  keyID: string;
  keys: CryptoKeyPair;
  attestation: (
    clientDataHash: Uint8Array,
    options?: { aaguid?: Uint8Array; counter?: number },
  ) => Promise<Uint8Array>;
  assertion: (
    clientDataHash: Uint8Array,
    counter: number,
  ) => Promise<Uint8Array>;
};

const productionAAGUID = bytes(new TextEncoder().encode("appattest"), [
  0,
  0,
  0,
  0,
  0,
  0,
  0,
]);
const developmentAAGUID = new TextEncoder().encode("appattestdevelop");

// Each run builds its own root, intermediate and device key, so no Apple
// private material, and no key file, is ever needed to exercise verification.
async function testDevice(): Promise<TestDevice> {
  const notBefore = new Date(now.getTime() - 86_400_000);
  const notAfter = new Date(now.getTime() + 86_400_000);
  const rootKeys = await crypto.subtle.generateKey(signing, true, [
    "sign",
    "verify",
  ]) as CryptoKeyPair;
  const root = await x509.X509CertificateGenerator.createSelfSigned({
    serialNumber: "01",
    name: "CN=Test App Attestation Root, O=Nina Tests",
    notBefore,
    notAfter,
    signingAlgorithm: signing,
    keys: rootKeys,
    extensions: [new x509.BasicConstraintsExtension(true, 2, true)],
  });
  const intermediateKeys = await crypto.subtle.generateKey(signing, true, [
    "sign",
    "verify",
  ]) as CryptoKeyPair;
  const intermediate = await x509.X509CertificateGenerator.create({
    serialNumber: "02",
    subject: "CN=Test App Attestation CA 1, O=Nina Tests",
    issuer: root.subject,
    notBefore,
    notAfter,
    signingAlgorithm: signing,
    publicKey: intermediateKeys.publicKey,
    signingKey: rootKeys.privateKey,
    extensions: [new x509.BasicConstraintsExtension(true, 0, true)],
  });
  const keys = await crypto.subtle.generateKey(signing, true, [
    "sign",
    "verify",
  ]) as CryptoKeyPair;
  const point = new Uint8Array(
    await crypto.subtle.exportKey("raw", keys.publicKey),
  );
  const keyIDBytes = await sha256(point);
  const rpIDHash = await sha256(new TextEncoder().encode(appAttestAppID));

  return {
    root,
    keyID: encodeBase64(keyIDBytes),
    keys,
    attestation: async (clientDataHash, options = {}) => {
      const counter = options.counter ?? 0;
      const authData = bytes(
        rpIDHash,
        [0x40],
        [
          counter >>> 24,
          (counter >> 16) & 0xff,
          (counter >> 8) & 0xff,
          counter & 0xff,
        ],
        options.aaguid ?? productionAAGUID,
        [0, 32],
        keyIDBytes,
      );
      const nonce = await sha256(bytes(authData, clientDataHash));
      const credential = await x509.X509CertificateGenerator.create({
        serialNumber: "03",
        subject: "CN=Test Device Key, O=Nina Tests",
        issuer: intermediate.subject,
        notBefore,
        notAfter,
        signingAlgorithm: signing,
        publicKey: keys.publicKey,
        signingKey: intermediateKeys.privateKey,
        extensions: [
          new x509.Extension(
            appAttestNonceOID,
            false,
            bytes([0x30, 0x24, 0xa1, 0x22, 0x04, 0x20], nonce).buffer,
          ),
        ],
      });
      return cbor(
        new Map<string, Encodable>([
          ["fmt", "apple-appattest"],
          [
            "attStmt",
            new Map<string, Encodable>([
              ["x5c", [
                new Uint8Array(credential.rawData),
                new Uint8Array(intermediate.rawData),
              ]],
              ["receipt", new Uint8Array([1, 2, 3])],
            ]),
          ],
          ["authData", authData],
        ]),
      );
    },
    assertion: async (clientDataHash, counter) => {
      const authenticatorData = bytes(rpIDHash, [0x40], [
        counter >>> 24,
        (counter >> 16) & 0xff,
        (counter >> 8) & 0xff,
        counter & 0xff,
      ]);
      const nonce = await sha256(bytes(authenticatorData, clientDataHash));
      const signature = new Uint8Array(
        await crypto.subtle.sign(
          { name: "ECDSA", hash: "SHA-256" },
          keys.privateKey,
          bytes(nonce),
        ),
      );
      return cbor(
        new Map<string, Encodable>([
          ["signature", rawToDER(signature)],
          ["authenticatorData", authenticatorData],
        ]),
      );
    },
  };
}

function challenge(fill: number): Uint8Array {
  return new Uint8Array(32).fill(fill);
}

async function registered(device: TestDevice) {
  const clientDataHash = await registrationClientDataHash(challenge(1), userID);
  return await verifyAttestation({
    attestation: await device.attestation(clientDataHash),
    keyID: device.keyID,
    clientDataHash,
    mode: "production",
    rootCertificates: [device.root],
    now,
  });
}

Deno.test("an attestation over this challenge and account registers the device key", async () => {
  const device = await testDevice();
  const verified = await registered(device);

  assertEquals(verified.environment, "production");
  const exported = new Uint8Array(
    await crypto.subtle.exportKey("spki", device.keys.publicKey),
  );
  assertEquals(verified.publicKeySPKI, encodeBase64(exported));
});

Deno.test("a development attestation is refused in production mode", async () => {
  const device = await testDevice();
  const clientDataHash = await registrationClientDataHash(challenge(1), userID);
  const attestation = await device.attestation(clientDataHash, {
    aaguid: developmentAAGUID,
  });

  await assertRejects(
    () =>
      verifyAttestation({
        attestation,
        keyID: device.keyID,
        clientDataHash,
        mode: "production",
        rootCertificates: [device.root],
        now,
      }),
    AppAttestError,
  );
  const development = await verifyAttestation({
    attestation,
    keyID: device.keyID,
    clientDataHash,
    mode: "development",
    rootCertificates: [device.root],
    now,
  });
  assertEquals(development.environment, "development");
});

Deno.test("an attestation for another account, another root or a used counter is refused", async () => {
  const device = await testDevice();
  const other = await testDevice();
  const clientDataHash = await registrationClientDataHash(challenge(1), userID);
  const attestation = await device.attestation(clientDataHash);

  for (
    const input of [
      {
        clientDataHash: await registrationClientDataHash(
          challenge(1),
          "10000000-0000-4000-9000-00000000000b",
        ),
        rootCertificates: [device.root],
        keyID: device.keyID,
        attestation,
      },
      {
        clientDataHash,
        rootCertificates: [other.root],
        keyID: device.keyID,
        attestation,
      },
      {
        clientDataHash,
        rootCertificates: [device.root],
        keyID: other.keyID,
        attestation,
      },
      {
        clientDataHash,
        rootCertificates: [device.root],
        keyID: device.keyID,
        attestation: await device.attestation(clientDataHash, { counter: 1 }),
      },
    ]
  ) {
    await assertRejects(
      () => verifyAttestation({ ...input, mode: "production", now }),
      AppAttestError,
    );
  }
});

Deno.test("an assertion over another challenge is refused", async () => {
  const device = await testDevice();
  const verified = await registered(device);
  const signalJSON = '{"outcome":"declined"}';
  const signed = await device.assertion(
    await assertionClientDataHash(challenge(2), signalJSON),
    1,
  );

  assertEquals(
    await verifyAssertion({
      assertion: signed,
      publicKeySPKI: verified.publicKeySPKI,
      storedCounter: 0,
      clientDataHash: await assertionClientDataHash(challenge(2), signalJSON),
    }),
    { counter: 1 },
  );
  await assertRejects(
    async () =>
      verifyAssertion({
        assertion: signed,
        publicKeySPKI: verified.publicKeySPKI,
        storedCounter: 0,
        clientDataHash: await assertionClientDataHash(challenge(3), signalJSON),
      }),
    AppAttestError,
  );
  await assertRejects(
    async () =>
      verifyAssertion({
        assertion: signed,
        publicKeySPKI: verified.publicKeySPKI,
        storedCounter: 0,
        clientDataHash: await assertionClientDataHash(
          challenge(2),
          '{"outcome":"sharing"}',
        ),
      }),
    AppAttestError,
  );
});

Deno.test("a counter that does not increase is refused", async () => {
  const device = await testDevice();
  const verified = await registered(device);
  const clientDataHash = await assertionClientDataHash(challenge(4), "{}");

  for (const counter of [5, 4]) {
    await assertRejects(
      async () =>
        verifyAssertion({
          assertion: await device.assertion(clientDataHash, counter),
          publicKeySPKI: verified.publicKeySPKI,
          storedCounter: 5,
          clientDataHash,
        }),
      AppAttestError,
    );
  }
});

Deno.test("insecure local mode refuses a non-loopback project URL", () => {
  assertEquals(
    resolveAppAttestMode("insecure-local", "http://127.0.0.1:54321"),
    "insecure-local",
  );
  assertEquals(
    resolveAppAttestMode("insecure-local", "http://kong:8000"),
    "insecure-local",
  );
  assertEquals(
    resolveAppAttestMode("development", "http://localhost:54321"),
    "development",
  );
  for (
    const url of [
      "https://apemftmlsjocvifbptum.supabase.co",
      "https://localhost:54321",
      "http://10.0.0.5:54321",
      "not a url",
    ]
  ) {
    assertEquals(resolveAppAttestMode("insecure-local", url), null, url);
    assertEquals(resolveAppAttestMode("development", url), null, url);
  }
  assertEquals(
    resolveAppAttestMode(
      "production",
      "https://apemftmlsjocvifbptum.supabase.co",
    ),
    "production",
  );
  assertEquals(resolveAppAttestMode(undefined, "http://localhost"), null);
  assertEquals(resolveAppAttestMode("sandbox", "http://localhost"), null);
});

Deno.test("the embedded root is Apple's self-signed App Attestation Root CA", async () => {
  const [root] = rootCertificatesFrom(undefined);
  assertEquals(
    root.subject,
    "CN=Apple App Attestation Root CA, O=Apple Inc., ST=California",
  );
  assert(await root.verify({ publicKey: root.publicKey, signatureOnly: true }));
  assertEquals(rootCertificatesFrom(appleAppAttestRootPEM).length, 1);
});

class BackendSpy implements AgeSignalBackend {
  events: string[] = [];
  consumed = new Set<string>();
  keys = new Map<string, StoredAttestKey>();
  recorded: MappedAge[] = [];
  reject = false;

  authenticatedUserID(accessToken: string) {
    return Promise.resolve(accessToken === "valid" ? userID : null);
  }
  issueChallenge() {
    this.events.push("challenge");
    return Promise.resolve({
      challenge: "A".repeat(43),
      expires_at: new Date(now.getTime() + 300_000).toISOString(),
    });
  }
  consumeChallenge(_user: string, value: string) {
    this.events.push("consume");
    if (this.consumed.has(value)) return Promise.resolve(false);
    this.consumed.add(value);
    return Promise.resolve(true);
  }
  registerKey(
    _user: string,
    keyID: string,
    publicKeySPKI: string,
    environment: "production" | "development",
  ) {
    this.events.push("register");
    this.keys.set(keyID, {
      public_key_spki: publicKeySPKI,
      counter: 0,
      environment,
    });
    return Promise.resolve();
  }
  getKey(_user: string, keyID: string) {
    return Promise.resolve(this.keys.get(keyID) ?? null);
  }
  advanceCounter(keyID: string, counter: number) {
    const key = this.keys.get(keyID);
    if (!key || counter <= key.counter) return Promise.resolve(false);
    key.counter = counter;
    return Promise.resolve(true);
  }
  recordAgeSignal(_user: string, age: MappedAge) {
    this.events.push("record");
    if (this.reject) return Promise.reject(new AgeSignalRejected());
    this.recorded.push(age);
    return Promise.resolve({
      status: age.status,
      band: age.band,
      changed: true,
      photo_cleanup_required: age.status !== "adult",
    });
  }
  deleteProfilePhotos() {
    this.events.push("photos");
    return Promise.resolve();
  }
  ageStatus() {
    return Promise.resolve({ status: "stored" });
  }
}

function signalRequest(body: unknown, token = "valid"): Request {
  return new Request("https://example.test/age-signal", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

const challengeText = "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE";
const declinedSignal = JSON.stringify({
  declaration: null,
  eligible_for_age_features: false,
  lower_bound: null,
  outcome: "declined",
  parental_controls: [],
  regulatory_features: [],
  upper_bound: null,
});
const minorSignal = JSON.stringify({
  declaration: "self_declared",
  eligible_for_age_features: null,
  lower_bound: 13,
  outcome: "sharing",
  parental_controls: [],
  regulatory_features: [],
  upper_bound: 15,
});

Deno.test("the age signal registers a key, verifies an assertion and records the mapped band", async () => {
  const device = await testDevice();
  const backend = new BackendSpy();
  const recordedLogs: unknown[] = [];
  const dependencies = {
    mode: "production" as const,
    backend,
    rootCertificates: [device.root],
    now: () => now,
    logRecorded: (event: unknown) => recordedLogs.push(event),
  };
  const challengeBytes = new Uint8Array(32).fill(1);

  const registration = await handleAgeSignalRequest(
    signalRequest({
      step: "register",
      challenge: challengeText,
      key_id: device.keyID,
      attestation: encodeBase64(
        await device.attestation(
          await registrationClientDataHash(challengeBytes, userID),
        ),
      ),
    }),
    dependencies,
  );
  assertEquals(registration.status, 200);
  assertEquals(await registration.json(), { registered: true });

  const signalChallenge = "AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI";
  const response = await handleAgeSignalRequest(
    signalRequest({
      step: "signal",
      challenge: signalChallenge,
      key_id: device.keyID,
      assertion: encodeBase64(
        await device.assertion(
          await assertionClientDataHash(
            new Uint8Array(32).fill(2),
            minorSignal,
          ),
          1,
        ),
      ),
      signal_json: minorSignal,
    }),
    dependencies,
  );

  assertEquals(response.status, 200);
  assertEquals(await response.json(), { age_status: { status: "stored" } });
  assertEquals(backend.recorded, [{
    status: "minor",
    band: "12_15",
    assurance: "self_declared",
    parentalControlsActive: false,
  }]);
  assert(backend.events.includes("photos"));
  assertEquals(recordedLogs, [{ changed: true, eligibleForAgeFeatures: null }]);
  assertFalse(JSON.stringify(recordedLogs).includes(userID));
});

Deno.test("an unknown device key is answered so the app can register again", async () => {
  const backend = new BackendSpy();
  const response = await handleAgeSignalRequest(
    signalRequest({
      step: "signal",
      challenge: challengeText,
      key_id: encodeBase64(new Uint8Array(32)),
      assertion: encodeBase64(new Uint8Array([0xa0])),
      signal_json: declinedSignal,
    }),
    { mode: "production", backend, now: () => now },
  );

  assertEquals(response.status, 401);
  assertEquals(await response.json(), { error: "app_attest_key_unknown" });
  assertFalse(backend.events.includes("record"));
});

Deno.test("insecure local mode accepts only its own key id and still records through the ratchet", async () => {
  const backend = new BackendSpy();
  const production = await handleAgeSignalRequest(
    signalRequest({
      step: "signal",
      challenge: challengeText,
      key_id: "insecure-local",
      assertion: "",
      signal_json: declinedSignal,
    }),
    { mode: "production", backend },
  );
  assertEquals(production.status, 401);

  backend.reject = true;
  const rejected = await handleAgeSignalRequest(
    signalRequest({
      step: "signal",
      challenge: challengeText,
      key_id: "insecure-local",
      assertion: "",
      signal_json: declinedSignal,
    }),
    { mode: "insecure-local", backend },
  );
  assertEquals(rejected.status, 409);
  assertEquals(await rejected.json(), {
    error: "age_signal_rejected",
    age_status: { status: "stored" },
  });

  const replay = await handleAgeSignalRequest(
    signalRequest({
      step: "signal",
      challenge: challengeText,
      key_id: "insecure-local",
      assertion: "",
      signal_json: declinedSignal,
    }),
    { mode: "insecure-local", backend },
  );
  assertEquals(replay.status, 401);
  assertEquals(await replay.json(), { error: "challenge_expired" });
});

Deno.test("the age signal refuses unknown fields, bad methods and missing configuration", async () => {
  const backend = new BackendSpy();
  const extra = await handleAgeSignalRequest(
    signalRequest({ step: "challenge", birth_date: "2010-01-01" }),
    { mode: "production", backend },
  );
  assertEquals(extra.status, 400);

  const method = await handleAgeSignalRequest(
    new Request("https://example.test/age-signal"),
    { mode: "production", backend },
  );
  assertEquals(method.status, 405);

  const unconfigured = await handleAgeSignalRequest(
    signalRequest({ step: "challenge" }),
    { mode: null, backend },
  );
  assertEquals(unconfigured.status, 503);
  assertEquals(await unconfigured.json(), { error: "service_not_configured" });

  const anonymous = await handleAgeSignalRequest(
    signalRequest({ step: "challenge" }, "invalid"),
    { mode: "production", backend },
  );
  assertEquals(anonymous.status, 401);

  const issued = await handleAgeSignalRequest(
    signalRequest({ step: "challenge" }),
    { mode: "production", backend },
  );
  assertEquals(issued.status, 200);
  assertEquals((await issued.json()).challenge.length, 43);
});

Deno.test("the age-signal endpoint is a thin adapter with content-free logs", async () => {
  const source = await Deno.readTextFile(
    new URL("../age-signal/index.ts", import.meta.url),
  );
  assert(source.includes("handleAgeSignalRequest(request"));
  assert(source.includes('"record_age_signal"'));
  assert(source.includes('"get_my_age_status"'));
  assertFalse(source.includes("node:crypto"));

  const logBodies = [...source.matchAll(
    /console\.(?:info|error)\(JSON\.stringify\(\{([\s\S]*?)\}\)\);/g,
  )].map((match) => match[1]);
  assertEquals(logBodies.length, 2);
  for (const body of logBodies) {
    for (
      const forbidden of [
        "userID",
        "user_id",
        "band",
        "bound",
        "key_id",
        "challenge",
      ]
    ) {
      assertFalse(body.includes(forbidden), forbidden);
    }
  }
});
