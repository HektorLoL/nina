import { assert, assertEquals, assertFalse, assertRejects } from "@std/assert";
// deno-lint-ignore no-import-prefix
import { p256, p384, p521 } from "npm:@noble/curves@2.4.0/nist.js";
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
  certificateSignedBy,
  decodeBase64,
  decodeCBOR,
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
const notBefore = new Date(now.getTime() - 86_400_000);
const notAfter = new Date(now.getTime() + 86_400_000);
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

function hex(value: string): Uint8Array<ArrayBuffer> {
  return new Uint8Array(
    (value.match(/../g) ?? []).map((pair) => Number.parseInt(pair, 16)),
  );
}

function indexOf(haystack: Uint8Array, needle: Uint8Array): number {
  for (let start = 0; start + needle.length <= haystack.length; start += 1) {
    if (needle.every((byte, index) => haystack[start + index] === byte)) {
      return start;
    }
  }
  return -1;
}

function replaced(
  source: Uint8Array<ArrayBuffer>,
  from: Uint8Array,
  to: Uint8Array,
): Uint8Array<ArrayBuffer> {
  const start = indexOf(source, from);
  assert(start >= 0 && from.length === to.length);
  const result = source.slice();
  result.set(to, start);
  return result;
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

function derHead(tag: number, length: number): number[] {
  if (length < 0x80) return [tag, length];
  if (length < 0x100) return [tag, 0x81, length];
  return [tag, 0x82, length >> 8, length & 0xff];
}

function der(tag: number, ...content: Uint8Array[]): Uint8Array<ArrayBuffer> {
  const body = bytes(...content);
  return bytes(derHead(tag, body.length), body);
}

function derSpan(element: Uint8Array, offset: number) {
  const first = element[offset + 1];
  if (!(first & 0x80)) return { header: 2, length: first };
  let length = 0;
  for (let index = 0; index < (first & 0x7f); index += 1) {
    length = length * 256 + element[offset + 2 + index];
  }
  return { header: 2 + (first & 0x7f), length };
}

function derContent(element: Uint8Array): Uint8Array<ArrayBuffer> {
  const { header, length } = derSpan(element, 0);
  return element.slice(header, header + length);
}

function derElements(element: Uint8Array): Uint8Array<ArrayBuffer>[] {
  const content = derContent(element);
  const children: Uint8Array<ArrayBuffer>[] = [];
  for (let offset = 0; offset < content.length;) {
    const { header, length } = derSpan(content, offset);
    children.push(content.slice(offset, offset + header + length));
    offset += header + length;
  }
  return children;
}

type Curve = "P-256" | "P-384" | "P-521";
type CAHash = "SHA-256" | "SHA-384";
type Hash = CAHash | "SHA-512";

const curves = { "P-256": p256, "P-384": p384, "P-521": p521 };
const publicKeyInfoPrefixes: Record<Curve, string> = {
  "P-256": "3059301306072a8648ce3d020106082a8648ce3d030107034200",
  "P-384": "3076301006072a8648ce3d020106052b81040022036200",
  "P-521": "30819b301006072a8648ce3d020106052b8104002303818600",
};
const signatureAlgorithms: Record<Hash, Uint8Array<ArrayBuffer>> = {
  "SHA-256": hex("300a06082a8648ce3d040302"),
  "SHA-384": hex("300a06082a8648ce3d040303"),
  "SHA-512": hex("300a06082a8648ce3d040304"),
};
const draftSigningKeys: Record<CAHash, Promise<CryptoKeyPair>> = {
  "SHA-256": crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign", "verify"],
  ) as Promise<CryptoKeyPair>,
  "SHA-384": crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-384" },
    false,
    ["sign", "verify"],
  ) as Promise<CryptoKeyPair>,
};

type Signer = {
  name: string;
  curve: Curve;
  secretKey: Uint8Array;
  publicKeyInfo: Uint8Array<ArrayBuffer>;
};

function signer(name: string, curve: Curve): Signer {
  const secretKey = curves[curve].utils.randomSecretKey();
  return {
    name,
    curve,
    secretKey,
    publicKeyInfo: bytes(
      hex(publicKeyInfoPrefixes[curve]),
      curves[curve].getPublicKey(secretKey, false),
    ),
  };
}

function certificateFrom(
  signedBytes: Uint8Array,
  algorithm: Uint8Array,
  signature: Uint8Array,
  unusedBits = 0,
): Uint8Array<ArrayBuffer> {
  return der(
    0x30,
    signedBytes,
    algorithm,
    der(0x03, bytes([unusedBits]), signature),
  );
}

function signatureOf(certificate: Uint8Array): Uint8Array<ArrayBuffer> {
  return derContent(derElements(certificate)[2]).slice(1);
}

async function signedWith(
  signedBytes: Uint8Array<ArrayBuffer>,
  issuer: Signer,
  hash: Hash,
  algorithm: Uint8Array = signatureAlgorithms[hash],
): Promise<Uint8Array<ArrayBuffer>> {
  const digest = new Uint8Array(await crypto.subtle.digest(hash, signedBytes));
  return certificateFrom(
    signedBytes,
    algorithm,
    curves[issuer.curve].sign(digest, issuer.secretKey, {
      prehash: false,
      format: "der",
    }),
  );
}

async function issue(input: {
  serialNumber: string;
  subject: string;
  issuer: Signer;
  publicKey: CryptoKey | Uint8Array<ArrayBuffer>;
  hash: CAHash;
  extensions: x509.Extension[];
}): Promise<Uint8Array<ArrayBuffer>> {
  const draft = await x509.X509CertificateGenerator.create({
    serialNumber: input.serialNumber,
    subject: input.subject,
    issuer: input.issuer.name,
    notBefore,
    notAfter,
    signingAlgorithm: { name: "ECDSA", hash: input.hash },
    publicKey: input.publicKey,
    signingKey: (await draftSigningKeys[input.hash]).privateKey,
    extensions: input.extensions,
  });
  const [signedBytes] = derElements(new Uint8Array(draft.rawData));
  return await signedWith(signedBytes, input.issuer, input.hash);
}

type ChainShape = {
  root: "P-256" | "P-384";
  caHash: CAHash;
  intermediate: "P-256" | "P-384";
  credentialHash: CAHash;
};

const appleChain: ChainShape = {
  root: "P-384",
  caHash: "SHA-384",
  intermediate: "P-384",
  credentialHash: "SHA-256",
};

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
async function testDevice(shape: ChainShape = appleChain): Promise<TestDevice> {
  const rootSigner = signer(
    "CN=Test App Attestation Root, O=Nina Tests",
    shape.root,
  );
  const root = new x509.X509Certificate(
    await issue({
      serialNumber: "01",
      subject: rootSigner.name,
      issuer: rootSigner,
      publicKey: rootSigner.publicKeyInfo,
      hash: shape.caHash,
      extensions: [new x509.BasicConstraintsExtension(true, 2, true)],
    }),
  );
  const caSigner = signer(
    "CN=Test App Attestation CA 1, O=Nina Tests",
    shape.intermediate,
  );
  const intermediate = await issue({
    serialNumber: "02",
    subject: caSigner.name,
    issuer: rootSigner,
    publicKey: caSigner.publicKeyInfo,
    hash: shape.caHash,
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
      const credential = await issue({
        serialNumber: "03",
        subject: "CN=Test Device Key, O=Nina Tests",
        issuer: caSigner,
        publicKey: keys.publicKey,
        hash: shape.credentialHash,
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
              ["x5c", [credential, intermediate]],
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
  const rootDER = new Uint8Array(root.rawData);
  assert(await certificateSignedBy(rootDER, rootDER));
  assertEquals(rootCertificatesFrom(appleAppAttestRootPEM).length, 1);
});

Deno.test("a device certificate a P-384 CA signs over SHA-256, as Apple's CA does, registers end to end", async () => {
  const device = await testDevice(appleChain);
  const clientDataHash = await registrationClientDataHash(challenge(1), userID);
  const attestation = await device.attestation(clientDataHash);
  const x5c = ((decodeCBOR(attestation) as Map<string, unknown>)
    .get("attStmt") as Map<string, unknown>).get("x5c") as Uint8Array<
      ArrayBuffer
    >[];

  assertEquals(derElements(x5c[0])[1], signatureAlgorithms["SHA-256"]);
  assertEquals(
    (new x509.X509Certificate(x5c[1]).publicKey.algorithm as EcKeyAlgorithm)
      .namedCurve,
    "P-384",
  );
  const verified = await verifyAttestation({
    attestation,
    keyID: device.keyID,
    clientDataHash,
    mode: "production",
    rootCertificates: [device.root],
    now,
  });
  assertEquals(verified.environment, "production");
});

Deno.test("a P-256 or P-384 issuer signing over SHA-256 or SHA-384 is verified in every pairing", async () => {
  for (const intermediate of ["P-256", "P-384"] as const) {
    for (const credentialHash of ["SHA-256", "SHA-384"] as const) {
      const device = await testDevice({
        root: intermediate === "P-256" ? "P-384" : "P-256",
        caHash: credentialHash === "SHA-256" ? "SHA-384" : "SHA-256",
        intermediate,
        credentialHash,
      });
      assertEquals(
        (await registered(device)).environment,
        "production",
        `${intermediate} ${credentialHash}`,
      );
    }
  }
});

async function appleShapedLink() {
  const ca = signer("CN=Test App Attestation CA 1, O=Nina Tests", "P-384");
  const issuer = await issue({
    serialNumber: "02",
    subject: ca.name,
    issuer: ca,
    publicKey: ca.publicKeyInfo,
    hash: "SHA-384",
    extensions: [new x509.BasicConstraintsExtension(true, 0, true)],
  });
  const deviceKeys = await crypto.subtle.generateKey(signing, false, [
    "sign",
    "verify",
  ]) as CryptoKeyPair;
  const certificate = await issue({
    serialNumber: "03",
    subject: "CN=Test Device Key, O=Nina Tests",
    issuer: ca,
    publicKey: deviceKeys.publicKey,
    hash: "SHA-256",
    extensions: [],
  });
  const [signedBytes, algorithm] = derElements(certificate);
  return {
    ca,
    issuer,
    certificate,
    signedBytes,
    algorithm,
    signature: signatureOf(certificate),
  };
}

Deno.test("a chain link with altered signed bytes, an altered signature or another issuer's key is refused", async () => {
  const link = await appleShapedLink();
  assert(await certificateSignedBy(link.certificate, link.issuer));

  const alteredSubject = link.signedBytes.slice();
  alteredSubject[
    indexOf(alteredSubject, new TextEncoder().encode("Test Device Key"))
  ] ^= 0x01;
  assertFalse(
    await certificateSignedBy(
      certificateFrom(alteredSubject, link.algorithm, link.signature),
      link.issuer,
    ),
  );

  const alteredSignature = link.signature.slice();
  alteredSignature[alteredSignature.length - 1] ^= 0x01;
  assertFalse(
    await certificateSignedBy(
      certificateFrom(link.signedBytes, link.algorithm, alteredSignature),
      link.issuer,
    ),
  );

  const impostor = signer(link.ca.name, "P-384");
  assertFalse(
    await certificateSignedBy(
      await signedWith(link.signedBytes, impostor, "SHA-256"),
      link.issuer,
    ),
  );
  const impostorIssuer = await issue({
    serialNumber: "02",
    subject: impostor.name,
    issuer: impostor,
    publicKey: impostor.publicKeyInfo,
    hash: "SHA-384",
    extensions: [new x509.BasicConstraintsExtension(true, 0, true)],
  });
  assertFalse(await certificateSignedBy(link.certificate, impostorIssuer));
});

Deno.test("a chain link signed with another algorithm or by an issuer on another curve is refused", async () => {
  const link = await appleShapedLink();

  const overSHA512 = replaced(
    link.signedBytes,
    signatureAlgorithms["SHA-256"],
    signatureAlgorithms["SHA-512"],
  );
  assertFalse(
    await certificateSignedBy(
      await signedWith(overSHA512, link.ca, "SHA-512"),
      link.issuer,
    ),
  );

  const namesAnotherAlgorithmInside = replaced(
    link.signedBytes,
    signatureAlgorithms["SHA-256"],
    signatureAlgorithms["SHA-384"],
  );
  assertFalse(
    await certificateSignedBy(
      await signedWith(
        namesAnotherAlgorithmInside,
        link.ca,
        "SHA-256",
        signatureAlgorithms["SHA-256"],
      ),
      link.issuer,
    ),
  );

  const wide = signer("CN=Test P-521 CA, O=Nina Tests", "P-521");
  const wideIssuer = await issue({
    serialNumber: "04",
    subject: wide.name,
    issuer: link.ca,
    publicKey: wide.publicKeyInfo,
    hash: "SHA-384",
    extensions: [new x509.BasicConstraintsExtension(true, 0, true)],
  });
  assertFalse(
    await certificateSignedBy(
      await signedWith(link.signedBytes, wide, "SHA-256"),
      wideIssuer,
    ),
  );
});

Deno.test("a chain link with truncated or trailing DER is refused", async () => {
  const link = await appleShapedLink();

  for (
    const [certificate, issuer] of [
      [link.certificate.slice(0, -1), link.issuer],
      [bytes(link.certificate, [0]), link.issuer],
      [link.certificate, link.issuer.slice(0, -1)],
      [link.certificate, bytes(link.issuer, [0])],
      [
        certificateFrom(link.signedBytes, link.algorithm, link.signature, 1),
        link.issuer,
      ],
      [
        certificateFrom(
          link.signedBytes,
          link.algorithm,
          bytes(link.signature, [0]),
        ),
        link.issuer,
      ],
      [new Uint8Array(), link.issuer],
    ]
  ) {
    assertFalse(await certificateSignedBy(certificate, issuer));
  }
});

Deno.test("a high-S signature from the CA is verified exactly as it arrived", async () => {
  const link = await appleShapedLink();
  const issued = p384.Signature.fromBytes(link.signature, "der");
  assertFalse(issued.hasHighS());

  const highS = new p384.Signature(issued.r, p384.Point.Fn.ORDER - issued.s)
    .toBytes("der");
  assert(p384.Signature.fromBytes(highS, "der").hasHighS());
  assert(
    await certificateSignedBy(
      certificateFrom(link.signedBytes, link.algorithm, highS),
      link.issuer,
    ),
  );
});

const nodeAppAttestAppID = "V8H6LQ9448.io.uebelacker.AppAttestExample";
const nodeAppAttestProduction = {
  attestation:
    "o2NmbXRvYXBwbGUtYXBwYXR0ZXN0Z2F0dFN0bXSiY3g1Y4JZAzgwggM0MIICuqADAgECAgYBjYVm/04wCgYIKoZIzj0EAwIwTzEjMCEGA1UEAwwaQXBwbGUgQXBwIEF0dGVzdGF0aW9uIENBIDExEzARBgNVBAoMCkFwcGxlIEluYy4xEzARBgNVBAgMCkNhbGlmb3JuaWEwHhcNMjQwMjA2MjEwODU2WhcNMjQxMjIxMTI0MjU2WjCBkTFJMEcGA1UEAwxANDgyZjNhMmQ5OWE4MTViMmZmMmIxNTlmN2IzYWZiOGExODA0NzRiMWNhZjE5YWMzNmQzYzBjYjQwOTAxMDliMzEaMBgGA1UECwwRQUFBIENlcnRpZmljYXRpb24xEzARBgNVBAoMCkFwcGxlIEluYy4xEzARBgNVBAgMCkNhbGlmb3JuaWEwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAATZgp7Aml8r0OItfeXeYu+8qIKJPFUMmoWYu7tMd6w/GWFjqyNY+Mp1FGika2RdQwAFMfyUdgBNeVv9gx3lViqGo4IBPTCCATkwDAYDVR0TAQH/BAIwADAOBgNVHQ8BAf8EBAMCBPAwgYoGCSqGSIb3Y2QIBQR9MHukAwIBCr+JMAMCAQG/iTEDAgEAv4kyAwIBAb+JMwMCAQG/iTQrBClWOEg2TFE5NDQ4LmlvLnVlYmVsYWNrZXIuQXBwQXR0ZXN0RXhhbXBsZaUGBARza3Mgv4k2AwIBBb+JNwMCAQC/iTkDAgEAv4k6AwIBAL+JOwMCAQAwVwYJKoZIhvdjZAgHBEowSL+KeAgEBjE3LjIuMb+IUAcCBQD/////v4p7BwQFMjFDNja/in0IBAYxNy4yLjG/in4DAgEAv4sMDwQNMjEuMy42Ni4wLjAsMDAzBgkqhkiG92NkCAIEJjAkoSIEIBwIwAN2H8j5gX6W4cgE7HGoHGurrAvt0S62royYkPclMAoGCCqGSM49BAMCA2gAMGUCMQDeNNEsh782FcjkD1biify1dyH1zeJYXNz87XmQeRsN2Vc2e8jifwcpp5SBtCMyXdoCMEtky4mPcswhzsy6egQgJjKbk1qdyewD+sA8vNNKb+CJBpxdB1lMC70E2A8C6MFmP1kCRzCCAkMwggHIoAMCAQICEAm6xeG8QBrZ1FOVvDgaCFQwCgYIKoZIzj0EAwMwUjEmMCQGA1UEAwwdQXBwbGUgQXBwIEF0dGVzdGF0aW9uIFJvb3QgQ0ExEzARBgNVBAoMCkFwcGxlIEluYy4xEzARBgNVBAgMCkNhbGlmb3JuaWEwHhcNMjAwMzE4MTgzOTU1WhcNMzAwMzEzMDAwMDAwWjBPMSMwIQYDVQQDDBpBcHBsZSBBcHAgQXR0ZXN0YXRpb24gQ0EgMTETMBEGA1UECgwKQXBwbGUgSW5jLjETMBEGA1UECAwKQ2FsaWZvcm5pYTB2MBAGByqGSM49AgEGBSuBBAAiA2IABK5bN6B3TXmyNY9A59HyJibxwl/vF4At6rOCalmHT/jSrRUleJqiZgQZEki2PLlnBp6Y02O9XjcPv6COMp6Ac6mF53Ruo1mi9m8p2zKvRV4hFljVZ6+eJn6yYU3CGmbOmaNmMGQwEgYDVR0TAQH/BAgwBgEB/wIBADAfBgNVHSMEGDAWgBSskRBTM72+aEH/pwyp5frq5eWKoTAdBgNVHQ4EFgQUPuNdHAQZqcm0MfiEdNbh4Vdy45swDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2kAMGYCMQC7voiNc40FAs+8/WZtCVdQNbzWhyw/hDBJJint0fkU6HmZHJrota7406hUM/e2DQYCMQCrOO3QzIHtAKRSw7pE+ZNjZVP+zCl/LrTfn16+WkrKtplcS4IN+QQ4b3gHu1iUObdncmVjZWlwdFkOsjCABgkqhkiG9w0BBwKggDCAAgEBMQ8wDQYJYIZIAWUDBAIBBQAwgAYJKoZIhvcNAQcBoIAkgASCA+gxggRtMDECAQICAQEEKVY4SDZMUTk0NDguaW8udWViZWxhY2tlci5BcHBBdHRlc3RFeGFtcGxlMIIDQgIBAwIBAQSCAzgwggM0MIICuqADAgECAgYBjYVm/04wCgYIKoZIzj0EAwIwTzEjMCEGA1UEAwwaQXBwbGUgQXBwIEF0dGVzdGF0aW9uIENBIDExEzARBgNVBAoMCkFwcGxlIEluYy4xEzARBgNVBAgMCkNhbGlmb3JuaWEwHhcNMjQwMjA2MjEwODU2WhcNMjQxMjIxMTI0MjU2WjCBkTFJMEcGA1UEAwxANDgyZjNhMmQ5OWE4MTViMmZmMmIxNTlmN2IzYWZiOGExODA0NzRiMWNhZjE5YWMzNmQzYzBjYjQwOTAxMDliMzEaMBgGA1UECwwRQUFBIENlcnRpZmljYXRpb24xEzARBgNVBAoMCkFwcGxlIEluYy4xEzARBgNVBAgMCkNhbGlmb3JuaWEwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAATZgp7Aml8r0OItfeXeYu+8qIKJPFUMmoWYu7tMd6w/GWFjqyNY+Mp1FGika2RdQwAFMfyUdgBNeVv9gx3lViqGo4IBPTCCATkwDAYDVR0TAQH/BAIwADAOBgNVHQ8BAf8EBAMCBPAwgYoGCSqGSIb3Y2QIBQR9MHukAwIBCr+JMAMCAQG/iTEDAgEAv4kyAwIBAb+JMwMCAQG/iTQrBClWOEg2TFE5NDQ4LmlvLnVlYmVsYWNrZXIuQXBwQXR0ZXN0RXhhbXBsZaUGBARza3Mgv4k2AwIBBb+JNwMCAQC/iTkDAgEAv4k6AwIBAL+JOwMCAQAwVwYJKoZIhvdjZAgHBEowSL+KeAgEBjE3LjIuMb+IUAcCBQD/////v4p7BwQFMjFDNja/in0IBAYxNy4yLjG/in4DAgEAv4sMDwQNMjEuMy42Ni4wLjAsMDAzBgkqhkiG92NkCAIEJjAkoSIEIBwIwAN2H8j5gX6W4cgE7HGoHGurrAvt0S62royYkPclMAoGCCqGSM49BAMCA2gAMGUCMQDeNNEsh782FcjkD1biify1dyH1zeJYXNz87XmQeRsN2Vc2e8jifwcpp5SBtCMyXdoCMEtky4mPcswhzsy6egQgJjKbk1qdyewD+sA8vNNKb+CJBpxdB1lMC70E2A8C6MFmPzAoAgEEAgEBBCA+nvULf/D5hTBPe2YIlcTC2gNOQ9r7OFtxUomNImwANzBgAgEFAgEBBFhjZjhsbVRXS3JHRTdORnl6c0RBY0JmeFJQczY5RmVYcUNEUU5OTXljSTJ1Q2NLSHI3TGJiMER2BIGJNzB6aTR1eUFVNEY3eGdCcHFBYVh1anZGUStFVkgrUT09MA4CAQYCAQEEBkFUVEVTVDASAgEHAgEBBApwcm9kdWN0aW9uMCACAQwCAQEEGDIwMjQtMDItMDdUMjE6MDg6NTYuMzA4WjAgAgEVAgEBBBgyMDI0LTA1LTA3VDIxOjA4OjU2LjMwOFoAAAAAAACggDCCA60wggNUoAMCAQICEH3NmVEtjH3NFgveDjiBekIwCgYIKoZIzj0EAwIwfDEwMC4GA1UEAwwnQXBwbGUgQXBwbGljYXRpb24gSW50ZWdyYXRpb24gQ0EgNSAtIEcxMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMjMwMzA4MTUyOTE3WhcNMjQwNDA2MTUyOTE2WjBaMTYwNAYDVQQDDC1BcHBsaWNhdGlvbiBBdHRlc3RhdGlvbiBGcmF1ZCBSZWNlaXB0IFNpZ25pbmcxEzARBgNVBAoMCkFwcGxlIEluYy4xCzAJBgNVBAYTAlVTMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE2pgoZ+9d0imsG72+nHEJ7T/XS6UZeRiwRGwaMi/mVldJ7Pmxu9UEcwJs5pTYHdPICN2Cfh6zy/vx/Sop4n8Q/aOCAdgwggHUMAwGA1UdEwEB/wQCMAAwHwYDVR0jBBgwFoAU2Rf+S2eQOEuS9NvO1VeAFAuPPckwQwYIKwYBBQUHAQEENzA1MDMGCCsGAQUFBzABhidodHRwOi8vb2NzcC5hcHBsZS5jb20vb2NzcDAzLWFhaWNhNWcxMDEwggEcBgNVHSAEggETMIIBDzCCAQsGCSqGSIb3Y2QFATCB/TCBwwYIKwYBBQUHAgIwgbYMgbNSZWxpYW5jZSBvbiB0aGlzIGNlcnRpZmljYXRlIGJ5IGFueSBwYXJ0eSBhc3N1bWVzIGFjY2VwdGFuY2Ugb2YgdGhlIHRoZW4gYXBwbGljYWJsZSBzdGFuZGFyZCB0ZXJtcyBhbmQgY29uZGl0aW9ucyBvZiB1c2UsIGNlcnRpZmljYXRlIHBvbGljeSBhbmQgY2VydGlmaWNhdGlvbiBwcmFjdGljZSBzdGF0ZW1lbnRzLjA1BggrBgEFBQcCARYpaHR0cDovL3d3dy5hcHBsZS5jb20vY2VydGlmaWNhdGVhdXRob3JpdHkwHQYDVR0OBBYEFEzxp58QYYoaOWTMbebbOwdil3a9MA4GA1UdDwEB/wQEAwIHgDAPBgkqhkiG92NkDA8EAgUAMAoGCCqGSM49BAMCA0cAMEQCIHrbZOJ1nE8FFv8sSdvzkCwvESymd45Qggp0g5ysO5vsAiBFNcdgKjJATfkqgWf8l7Zy4AmZ1CmKlucFy+0JcBdQjTCCAvkwggJ/oAMCAQICEFb7g9Qr/43DN5kjtVqubr0wCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTkwMzIyMTc1MzMzWhcNMzQwMzIyMDAwMDAwWjB8MTAwLgYDVQQDDCdBcHBsZSBBcHBsaWNhdGlvbiBJbnRlZ3JhdGlvbiBDQSA1IC0gRzExJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABJLOY719hrGrKAo7HOGv+wSUgJGs9jHfpssoNW9ES+Eh5VfdEo2NuoJ8lb5J+r4zyq7NBBnxL0Ml+vS+s8uDfrqjgfcwgfQwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBS7sN6hWDOImqSKmd6+veuv2sskqzBGBggrBgEFBQcBAQQ6MDgwNgYIKwYBBQUHMAGGKmh0dHA6Ly9vY3NwLmFwcGxlLmNvbS9vY3NwMDMtYXBwbGVyb290Y2FnMzA3BgNVHR8EMDAuMCygKqAohiZodHRwOi8vY3JsLmFwcGxlLmNvbS9hcHBsZXJvb3RjYWczLmNybDAdBgNVHQ4EFgQU2Rf+S2eQOEuS9NvO1VeAFAuPPckwDgYDVR0PAQH/BAQDAgEGMBAGCiqGSIb3Y2QGAgMEAgUAMAoGCCqGSM49BAMDA2gAMGUCMQCNb6afoeDk7FtOc4qSfz14U5iP9NofWB7DdUr+OKhMKoMaGqoNpmRt4bmT6NFVTO0CMGc7LLTh6DcHd8vV7HaoGjpVOz81asjF5pKw4WG+gElp5F8rqWzhEQKqzGHZOLdzSjCCAkMwggHJoAMCAQICCC3F/IjSxUuVMAoGCCqGSM49BAMDMGcxGzAZBgNVBAMMEkFwcGxlIFJvb3QgQ0EgLSBHMzEmMCQGA1UECwwdQXBwbGUgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkxEzARBgNVBAoMCkFwcGxlIEluYy4xCzAJBgNVBAYTAlVTMB4XDTE0MDQzMDE4MTkwNloXDTM5MDQzMDE4MTkwNlowZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwdjAQBgcqhkjOPQIBBgUrgQQAIgNiAASY6S89QHKk7ZMicoETHN0QlfHFo05x3BQW2Q7lpgUqd2R7X04407scRLV/9R+2MmJdyemEW08wTxFaAP1YWAyl9Q8sTQdHE3Xal5eXbzFc7SudeyA72LlU2V6ZpDpRCjGjQjBAMB0GA1UdDgQWBBS7sN6hWDOImqSKmd6+veuv2sskqzAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIBBjAKBggqhkjOPQQDAwNoADBlAjEAg+nBxBZeGl00GNnt7/RsDgBGS7jfskYRxQ/95nqMoaZrzsID1Jz1k8Z0uGrfqiMVAjBtZooQytQN1E/NjUM+tIpjpTNu423aF7dkH8hTJvmIYnQ5Cxdby1GoDOgYA+eisigAADGB/DCB+QIBATCBkDB8MTAwLgYDVQQDDCdBcHBsZSBBcHBsaWNhdGlvbiBJbnRlZ3JhdGlvbiBDQSA1IC0gRzExJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUwIQfc2ZUS2Mfc0WC94OOIF6QjANBglghkgBZQMEAgEFADAKBggqhkjOPQQDAgRGMEQCIHSUEAahN7NurrzYZn0Jdof4HOHYYoWEdF143LiKZtyQAiAmQTitB7NJuQeGPmoGdR6eEk+LcvfJK5CHYQdzJA6X+gAAAAAAAGhhdXRoRGF0YVikyj3cO094ro3BWWx1ax19Jg0jKzZrOT8xG6xW0D0QOqxAAAAAAGFwcGF0dGVzdAAAAAAAAAAAIEgvOi2ZqBWy/ysVn3s6+4oYBHSxyvGaw208DLQJAQmzpQECAyYgASFYINmCnsCaXyvQ4i195d5i77yogok8VQyahZi7u0x3rD8ZIlggYWOrI1j4ynUUaKRrZF1DAAUx/JR2AE15W/2DHeVWKoY=",
  keyId: "SC86LZmoFbL/KxWfezr7ihgEdLHK8ZrDbTwMtAkBCbM=",
  challenge: "ZGU1ZTAzNTktODRmNy00ZGQ3LWE5OGQtNTM2M2U5NDE1ZmIx",
};
const nodeAppAttestDevelopment = {
  attestation:
    "o2NmbXRvYXBwbGUtYXBwYXR0ZXN0Z2F0dFN0bXSiY3g1Y4JZAzgwggM0MIICuqADAgECAgYBjXXNniswCgYIKoZIzj0EAwIwTzEjMCEGA1UEAwwaQXBwbGUgQXBwIEF0dGVzdGF0aW9uIENBIDExEzARBgNVBAoMCkFwcGxlIEluYy4xEzARBgNVBAgMCkNhbGlmb3JuaWEwHhcNMjQwMjAzMjAyNzA2WhcNMjUwMTA4MDYyMTA2WjCBkTFJMEcGA1UEAwxAYjNmZDc3ZTBjNmRlMTA0NjQzNjRhMGFmMzkzN2ZlOGQ5ODBkODY5YTAzYzFkNWQ5ZjFjMjlmNGYyOWJjMTU0ODEaMBgGA1UECwwRQUFBIENlcnRpZmljYXRpb24xEzARBgNVBAoMCkFwcGxlIEluYy4xEzARBgNVBAgMCkNhbGlmb3JuaWEwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAATUbRMd9sTNTCHp+VvhPrOISWBBq6xvez0e2WTNoFHd1iPc7BA0QRR6BudOs2wJsXdtLx8XG7CmOF1/RxA5tK/vo4IBPTCCATkwDAYDVR0TAQH/BAIwADAOBgNVHQ8BAf8EBAMCBPAwgYoGCSqGSIb3Y2QIBQR9MHukAwIBCr+JMAMCAQG/iTEDAgEAv4kyAwIBAb+JMwMCAQG/iTQrBClWOEg2TFE5NDQ4LmlvLnVlYmVsYWNrZXIuQXBwQXR0ZXN0RXhhbXBsZaUGBARza3Mgv4k2AwIBBb+JNwMCAQC/iTkDAgEAv4k6AwIBAL+JOwMCAQAwVwYJKoZIhvdjZAgHBEowSL+KeAgEBjE3LjIuMb+IUAcCBQD/////v4p7BwQFMjFDNja/in0IBAYxNy4yLjG/in4DAgEAv4sMDwQNMjEuMy42Ni4wLjAsMDAzBgkqhkiG92NkCAIEJjAkoSIEIM5NSa3vXruGr5szchuQ4E6N36Nm/mZlkJflZq9Sdm4ZMAoGCCqGSM49BAMCA2gAMGUCMHlYC0KJPqTmF+QSnMlf3MH2XPSrSRnjyNI5yaSGNqeIkHlLJJQj3IUnMKA8JsCXsAIxAIo0HeGatVEyQhqrS9Ug9/3HbMXTGXqxRcdnT3XrA/atw4UYzwsK/vEEbRItNrbsKFkCRzCCAkMwggHIoAMCAQICEAm6xeG8QBrZ1FOVvDgaCFQwCgYIKoZIzj0EAwMwUjEmMCQGA1UEAwwdQXBwbGUgQXBwIEF0dGVzdGF0aW9uIFJvb3QgQ0ExEzARBgNVBAoMCkFwcGxlIEluYy4xEzARBgNVBAgMCkNhbGlmb3JuaWEwHhcNMjAwMzE4MTgzOTU1WhcNMzAwMzEzMDAwMDAwWjBPMSMwIQYDVQQDDBpBcHBsZSBBcHAgQXR0ZXN0YXRpb24gQ0EgMTETMBEGA1UECgwKQXBwbGUgSW5jLjETMBEGA1UECAwKQ2FsaWZvcm5pYTB2MBAGByqGSM49AgEGBSuBBAAiA2IABK5bN6B3TXmyNY9A59HyJibxwl/vF4At6rOCalmHT/jSrRUleJqiZgQZEki2PLlnBp6Y02O9XjcPv6COMp6Ac6mF53Ruo1mi9m8p2zKvRV4hFljVZ6+eJn6yYU3CGmbOmaNmMGQwEgYDVR0TAQH/BAgwBgEB/wIBADAfBgNVHSMEGDAWgBSskRBTM72+aEH/pwyp5frq5eWKoTAdBgNVHQ4EFgQUPuNdHAQZqcm0MfiEdNbh4Vdy45swDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2kAMGYCMQC7voiNc40FAs+8/WZtCVdQNbzWhyw/hDBJJint0fkU6HmZHJrota7406hUM/e2DQYCMQCrOO3QzIHtAKRSw7pE+ZNjZVP+zCl/LrTfn16+WkrKtplcS4IN+QQ4b3gHu1iUObdncmVjZWlwdFkOrzCABgkqhkiG9w0BBwKggDCAAgEBMQ8wDQYJYIZIAWUDBAIBBQAwgAYJKoZIhvcNAQcBoIAkgASCA+gxggRqMDECAQICAQEEKVY4SDZMUTk0NDguaW8udWViZWxhY2tlci5BcHBBdHRlc3RFeGFtcGxlMIIDQgIBAwIBAQSCAzgwggM0MIICuqADAgECAgYBjXXNniswCgYIKoZIzj0EAwIwTzEjMCEGA1UEAwwaQXBwbGUgQXBwIEF0dGVzdGF0aW9uIENBIDExEzARBgNVBAoMCkFwcGxlIEluYy4xEzARBgNVBAgMCkNhbGlmb3JuaWEwHhcNMjQwMjAzMjAyNzA2WhcNMjUwMTA4MDYyMTA2WjCBkTFJMEcGA1UEAwxAYjNmZDc3ZTBjNmRlMTA0NjQzNjRhMGFmMzkzN2ZlOGQ5ODBkODY5YTAzYzFkNWQ5ZjFjMjlmNGYyOWJjMTU0ODEaMBgGA1UECwwRQUFBIENlcnRpZmljYXRpb24xEzARBgNVBAoMCkFwcGxlIEluYy4xEzARBgNVBAgMCkNhbGlmb3JuaWEwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAATUbRMd9sTNTCHp+VvhPrOISWBBq6xvez0e2WTNoFHd1iPc7BA0QRR6BudOs2wJsXdtLx8XG7CmOF1/RxA5tK/vo4IBPTCCATkwDAYDVR0TAQH/BAIwADAOBgNVHQ8BAf8EBAMCBPAwgYoGCSqGSIb3Y2QIBQR9MHukAwIBCr+JMAMCAQG/iTEDAgEAv4kyAwIBAb+JMwMCAQG/iTQrBClWOEg2TFE5NDQ4LmlvLnVlYmVsYWNrZXIuQXBwQXR0ZXN0RXhhbXBsZaUGBARza3Mgv4k2AwIBBb+JNwMCAQC/iTkDAgEAv4k6AwIBAL+JOwMCAQAwVwYJKoZIhvdjZAgHBEowSL+KeAgEBjE3LjIuMb+IUAcCBQD/////v4p7BwQFMjFDNja/in0IBAYxNy4yLjG/in4DAgEAv4sMDwQNMjEuMy42Ni4wLjAsMDAzBgkqhkiG92NkCAIEJjAkoSIEIM5NSa3vXruGr5szchuQ4E6N36Nm/mZlkJflZq9Sdm4ZMAoGCCqGSM49BAMCA2gAMGUCMHlYC0KJPqTmF+QSnMlf3MH2XPSrSRnjyNI5yaSGNqeIkHlLJJQj3IUnMKA8JsCXsAIxAIo0HeGatVEyQhqrS9Ug9/3HbMXTGXqxRcdnT3XrA/atw4UYzwsK/vEEbRItNrbsKDAoAgEEAgEBBCCU3wfNkLCWvlrQ0iwz2h6NdnA1ymMXJeLGeG8gFJmUITBgAgEFAgEBBFgxZmt5Q2hVMUIwNWkwNW5Rem85MlErajZWbDR6U3duNytVb0h6bVd0ckJuN1lyaDBNNTFveFF3BIGGbXpJV2tTUFhqK1RJOC9jNFRHOHdCTmhkV1ZJZ0VsUT09MA4CAQYCAQEEBkFUVEVTVDAPAgEHAgEBBAdzYW5kYm94MCACAQwCAQEEGDIwMjQtMDItMDRUMjA6Mjc6MDYuMTkzWjAgAgEVAgEBBBgyMDI0LTA1LTA0VDIwOjI3OjA2LjE5M1oAAAAAAACggDCCA60wggNUoAMCAQICEH3NmVEtjH3NFgveDjiBekIwCgYIKoZIzj0EAwIwfDEwMC4GA1UEAwwnQXBwbGUgQXBwbGljYXRpb24gSW50ZWdyYXRpb24gQ0EgNSAtIEcxMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMjMwMzA4MTUyOTE3WhcNMjQwNDA2MTUyOTE2WjBaMTYwNAYDVQQDDC1BcHBsaWNhdGlvbiBBdHRlc3RhdGlvbiBGcmF1ZCBSZWNlaXB0IFNpZ25pbmcxEzARBgNVBAoMCkFwcGxlIEluYy4xCzAJBgNVBAYTAlVTMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE2pgoZ+9d0imsG72+nHEJ7T/XS6UZeRiwRGwaMi/mVldJ7Pmxu9UEcwJs5pTYHdPICN2Cfh6zy/vx/Sop4n8Q/aOCAdgwggHUMAwGA1UdEwEB/wQCMAAwHwYDVR0jBBgwFoAU2Rf+S2eQOEuS9NvO1VeAFAuPPckwQwYIKwYBBQUHAQEENzA1MDMGCCsGAQUFBzABhidodHRwOi8vb2NzcC5hcHBsZS5jb20vb2NzcDAzLWFhaWNhNWcxMDEwggEcBgNVHSAEggETMIIBDzCCAQsGCSqGSIb3Y2QFATCB/TCBwwYIKwYBBQUHAgIwgbYMgbNSZWxpYW5jZSBvbiB0aGlzIGNlcnRpZmljYXRlIGJ5IGFueSBwYXJ0eSBhc3N1bWVzIGFjY2VwdGFuY2Ugb2YgdGhlIHRoZW4gYXBwbGljYWJsZSBzdGFuZGFyZCB0ZXJtcyBhbmQgY29uZGl0aW9ucyBvZiB1c2UsIGNlcnRpZmljYXRlIHBvbGljeSBhbmQgY2VydGlmaWNhdGlvbiBwcmFjdGljZSBzdGF0ZW1lbnRzLjA1BggrBgEFBQcCARYpaHR0cDovL3d3dy5hcHBsZS5jb20vY2VydGlmaWNhdGVhdXRob3JpdHkwHQYDVR0OBBYEFEzxp58QYYoaOWTMbebbOwdil3a9MA4GA1UdDwEB/wQEAwIHgDAPBgkqhkiG92NkDA8EAgUAMAoGCCqGSM49BAMCA0cAMEQCIHrbZOJ1nE8FFv8sSdvzkCwvESymd45Qggp0g5ysO5vsAiBFNcdgKjJATfkqgWf8l7Zy4AmZ1CmKlucFy+0JcBdQjTCCAvkwggJ/oAMCAQICEFb7g9Qr/43DN5kjtVqubr0wCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTkwMzIyMTc1MzMzWhcNMzQwMzIyMDAwMDAwWjB8MTAwLgYDVQQDDCdBcHBsZSBBcHBsaWNhdGlvbiBJbnRlZ3JhdGlvbiBDQSA1IC0gRzExJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABJLOY719hrGrKAo7HOGv+wSUgJGs9jHfpssoNW9ES+Eh5VfdEo2NuoJ8lb5J+r4zyq7NBBnxL0Ml+vS+s8uDfrqjgfcwgfQwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBS7sN6hWDOImqSKmd6+veuv2sskqzBGBggrBgEFBQcBAQQ6MDgwNgYIKwYBBQUHMAGGKmh0dHA6Ly9vY3NwLmFwcGxlLmNvbS9vY3NwMDMtYXBwbGVyb290Y2FnMzA3BgNVHR8EMDAuMCygKqAohiZodHRwOi8vY3JsLmFwcGxlLmNvbS9hcHBsZXJvb3RjYWczLmNybDAdBgNVHQ4EFgQU2Rf+S2eQOEuS9NvO1VeAFAuPPckwDgYDVR0PAQH/BAQDAgEGMBAGCiqGSIb3Y2QGAgMEAgUAMAoGCCqGSM49BAMDA2gAMGUCMQCNb6afoeDk7FtOc4qSfz14U5iP9NofWB7DdUr+OKhMKoMaGqoNpmRt4bmT6NFVTO0CMGc7LLTh6DcHd8vV7HaoGjpVOz81asjF5pKw4WG+gElp5F8rqWzhEQKqzGHZOLdzSjCCAkMwggHJoAMCAQICCC3F/IjSxUuVMAoGCCqGSM49BAMDMGcxGzAZBgNVBAMMEkFwcGxlIFJvb3QgQ0EgLSBHMzEmMCQGA1UECwwdQXBwbGUgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkxEzARBgNVBAoMCkFwcGxlIEluYy4xCzAJBgNVBAYTAlVTMB4XDTE0MDQzMDE4MTkwNloXDTM5MDQzMDE4MTkwNlowZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwdjAQBgcqhkjOPQIBBgUrgQQAIgNiAASY6S89QHKk7ZMicoETHN0QlfHFo05x3BQW2Q7lpgUqd2R7X04407scRLV/9R+2MmJdyemEW08wTxFaAP1YWAyl9Q8sTQdHE3Xal5eXbzFc7SudeyA72LlU2V6ZpDpRCjGjQjBAMB0GA1UdDgQWBBS7sN6hWDOImqSKmd6+veuv2sskqzAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIBBjAKBggqhkjOPQQDAwNoADBlAjEAg+nBxBZeGl00GNnt7/RsDgBGS7jfskYRxQ/95nqMoaZrzsID1Jz1k8Z0uGrfqiMVAjBtZooQytQN1E/NjUM+tIpjpTNu423aF7dkH8hTJvmIYnQ5Cxdby1GoDOgYA+eisigAADGB/DCB+QIBATCBkDB8MTAwLgYDVQQDDCdBcHBsZSBBcHBsaWNhdGlvbiBJbnRlZ3JhdGlvbiBDQSA1IC0gRzExJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUwIQfc2ZUS2Mfc0WC94OOIF6QjANBglghkgBZQMEAgEFADAKBggqhkjOPQQDAgRGMEQCICDRBwL6EXnsaAyzRlUAprVpCVEQPbmEqS5SnOH0MKUpAiBpPwpQmtHCjZDbJ+wHnQ9KNWimtKsiJgn+un48tVlFSgAAAAAAAGhhdXRoRGF0YVikyj3cO094ro3BWWx1ax19Jg0jKzZrOT8xG6xW0D0QOqxAAAAAAGFwcGF0dGVzdGRldmVsb3AAILP9d+DG3hBGQ2Sgrzk3/o2YDYaaA8HV2fHCn08pvBVIpQECAyYgASFYINRtEx32xM1MIen5W+E+s4hJYEGrrG97PR7ZZM2gUd3WIlggI9zsEDRBFHoG506zbAmxd20vHxcbsKY4XX9HEDm0r+8=",
  keyId: "s/134MbeEEZDZKCvOTf+jZgNhpoDwdXZ8cKfTym8FUg=",
  challenge: "NmY0NmFhZWItMzk4OS00NWRiLThjMjQtNmNjODhhNzZlNzg5",
};

async function appleSample(
  sample: { attestation: string; keyId: string; challenge: string },
  mode: "production" | "development",
  at: string,
) {
  return {
    attestation: decodeBase64(sample.attestation) ?? new Uint8Array(),
    keyID: sample.keyId,
    clientDataHash: await sha256(
      decodeBase64(sample.challenge) ?? new Uint8Array(),
    ),
    mode,
    rootCertificates: rootCertificatesFrom(undefined),
    now: new Date(at),
    appID: nodeAppAttestAppID as string | undefined,
  };
}

Deno.test("a real production attestation from https://github.com/uebelack/node-app-attest/blob/8cbada20bf489e71b5cb36aeab68ac92afbc4ba1/test/fixtures/attestation-production.json verifies against Apple's root", async () => {
  const sample = await appleSample(
    nodeAppAttestProduction,
    "production",
    "2024-02-07T21:11:56Z",
  );
  const verified = await verifyAttestation(sample);

  assertEquals(verified.environment, "production");
  assertEquals(decodeBase64(verified.publicKeySPKI)?.byteLength, 91);
  for (
    const refused of [
      { ...sample, appID: undefined },
      { ...sample, mode: "development" as const },
      { ...sample, now: new Date("2024-12-22T00:00:00Z") },
      {
        ...sample,
        clientDataHash: await sha256(new TextEncoder().encode("another")),
      },
    ]
  ) {
    await assertRejects(() => verifyAttestation(refused), AppAttestError);
  }
});

Deno.test("a real development attestation from https://github.com/uebelack/node-app-attest/blob/8cbada20bf489e71b5cb36aeab68ac92afbc4ba1/test/fixtures/attestation-development.json verifies only in development mode", async () => {
  const sample = await appleSample(
    nodeAppAttestDevelopment,
    "development",
    "2024-02-04T20:27:06Z",
  );

  assertEquals((await verifyAttestation(sample)).environment, "development");
  await assertRejects(
    () => verifyAttestation({ ...sample, mode: "production" }),
    AppAttestError,
  );
});

Deno.test("chain links are verified on their own DER in pure JS, never through the runtime's WebCrypto", async () => {
  const source = await Deno.readTextFile(
    new URL("./app-attest.ts", import.meta.url),
  );
  assert(source.includes('from "npm:@noble/curves@2.4.0/nist.js"'));
  assert(source.includes('{ prehash: false, lowS: false, format: "der" }'));
  assertFalse(source.includes("certificate.verify("));
  assertFalse(source.includes(".tbs"));
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
