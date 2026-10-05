import { assert, assertEquals, assertFalse } from "@std/assert";
import type { AppleRevocationResult } from "./apple-sign-in-revocation.ts";
import {
  type AppleTokenRevocationFailureEvent,
  type DeleteAccountBackend,
  type DeleteAccountFailureEvent,
  deleteAccountInOrder,
  handleDeleteAccountRequest,
  maxDeleteAccountRequestBytes,
  parseDeleteAccountBody,
} from "./delete-account.ts";

const userID = "10000000-0000-4000-9000-000000000001";
const wardID = "10000000-0000-4000-9000-000000000002";
const wardMemberID = "2000000a-0000-4000-9000-00000000000b";
const appleCode = "c0de.throwaway-_1";
const requestID = "delete-request-test";

class DeleteAccountBackendSpy implements DeleteAccountBackend {
  events: string[] = [];
  removedPaths: string[][] = [];
  authenticatedID: string | null = userID;
  guardianWard: string | null = wardID;
  failure?:
    | "authentication"
    | "guardian"
    | "list"
    | "remove"
    | "database"
    | "auth_user";
  listResult: (offset: number, limit: number) => string[] = () => [];

  authenticatedUserID(accessToken: string): Promise<string | null> {
    this.events.push(`authenticate:${accessToken}`);
    if (this.failure === "authentication") {
      return Promise.reject(new Error("unavailable"));
    }
    return Promise.resolve(this.authenticatedID);
  }

  authorizeGuardianAccountDeletion(
    guardianUserID: string,
    memberID: string,
  ): Promise<string | null> {
    this.events.push(`guardian:${guardianUserID}:${memberID}`);
    if (this.failure === "guardian") {
      return Promise.reject(new Error("unavailable"));
    }
    return Promise.resolve(this.guardianWard);
  }

  listProfilePhotoNames(
    _userID: string,
    offset: number,
    limit: number,
  ): Promise<string[]> {
    this.events.push(`list:${offset}:${limit}`);
    if (this.failure === "list") {
      return Promise.reject(new Error("unavailable"));
    }
    return Promise.resolve(this.listResult(offset, limit));
  }

  removeProfilePhotoPaths(paths: string[]): Promise<void> {
    this.events.push(`remove:${paths.length}`);
    if (this.failure === "remove") {
      return Promise.reject(new Error("unavailable"));
    }
    this.removedPaths.push(paths);
    return Promise.resolve();
  }

  prepareAccountDeletion(receivedUserID: string): Promise<void> {
    this.events.push(`database:${receivedUserID}`);
    if (this.failure === "database") {
      return Promise.reject(new Error("unavailable"));
    }
    return Promise.resolve();
  }

  deleteAuthUser(receivedUserID: string): Promise<void> {
    this.events.push(`auth_user:${receivedUserID}`);
    if (this.failure === "auth_user") {
      return Promise.reject(new Error("unavailable"));
    }
    return Promise.resolve();
  }
}

function deletionRequest(
  body = JSON.stringify({ confirmation: "delete" }),
  headers: HeadersInit = {},
): Request {
  const requestHeaders = new Headers({
    Authorization: "Bearer header.payload.signature",
    "Content-Type": "application/json",
  });
  new Headers(headers).forEach((value, key) => requestHeaders.set(key, value));
  return new Request("https://example.test/delete-account", {
    method: "POST",
    headers: requestHeaders,
    body,
  });
}

async function responseJSON(
  response: Response,
): Promise<Record<string, unknown>> {
  return await response.json() as Record<string, unknown>;
}

Deno.test("account deletion is POST-only and returns baseline response headers", async () => {
  const response = await handleDeleteAccountRequest(
    new Request("https://example.test/delete-account"),
    { makeRequestID: () => requestID },
  );

  assertEquals(response.status, 405);
  assertEquals(response.headers.get("Allow"), "POST");
  assertEquals(response.headers.get("Cache-Control"), "no-store");
  assertEquals(response.headers.get("X-Content-Type-Options"), "nosniff");
  assertEquals(response.headers.get("X-Request-ID"), requestID);
  assertEquals(await responseJSON(response), { error: "method_not_allowed" });
});

Deno.test("account deletion requires bounded application/json", async () => {
  const backend = new DeleteAccountBackendSpy();
  const missingContentType = deletionRequest();
  missingContentType.headers.delete("Content-Type");

  const unsupported = await handleDeleteAccountRequest(missingContentType, {
    backend,
  });
  assertEquals(unsupported.status, 415);

  const oversized = await handleDeleteAccountRequest(
    deletionRequest("x".repeat(maxDeleteAccountRequestBytes + 1)),
    { backend },
  );
  assertEquals(oversized.status, 413);

  const malformed = await handleDeleteAccountRequest(deletionRequest("{"), {
    backend,
  });
  assertEquals(malformed.status, 400);
  assertEquals(await responseJSON(malformed), { error: "invalid_request" });
  assertEquals(backend.events, []);
});

Deno.test("account deletion requires an exact destructive confirmation", async () => {
  const backend = new DeleteAccountBackendSpy();
  const payloads = [
    {},
    { confirmation: "DELETE" },
    { confirmation: "delete", unexpected: true },
    ["delete"],
  ];

  for (const payload of payloads) {
    const response = await handleDeleteAccountRequest(
      deletionRequest(JSON.stringify(payload)),
      { backend },
    );
    assertEquals(response.status, 400);
    assertEquals(await responseJSON(response), {
      error: "confirmation_required",
    });
  }
  assertEquals(backend.events, []);
});

Deno.test("account deletion rejects missing or malformed bearer credentials", async () => {
  const backend = new DeleteAccountBackendSpy();
  for (
    const authorization of ["", "Basic abc", "Bearer  token", "Bearer a b"]
  ) {
    const request = deletionRequest();
    if (authorization) request.headers.set("Authorization", authorization);
    else request.headers.delete("Authorization");

    const response = await handleDeleteAccountRequest(request, { backend });
    assertEquals(response.status, 401);
    assertEquals(await responseJSON(response), { error: "not_authenticated" });
  }
  assertEquals(backend.events, []);
});

Deno.test("account deletion fails closed when its privileged backend is unavailable", async () => {
  const failures: DeleteAccountFailureEvent[] = [];
  const response = await handleDeleteAccountRequest(deletionRequest(), {
    makeRequestID: () => requestID,
    logFailure: (event) => failures.push(event),
  });

  assertEquals(response.status, 503);
  assertEquals(response.headers.get("Retry-After"), "60");
  assertEquals(await responseJSON(response), {
    error: "service_not_configured",
  });
  assertEquals(failures, [{ requestID, stage: "configuration" }]);
});

Deno.test("account deletion treats an invalid access token as unauthenticated", async () => {
  const backend = new DeleteAccountBackendSpy();
  backend.authenticatedID = null;
  const response = await handleDeleteAccountRequest(deletionRequest(), {
    backend,
  });

  assertEquals(response.status, 401);
  assertEquals(await responseJSON(response), { error: "not_authenticated" });
  assertEquals(backend.events, ["authenticate:header.payload.signature"]);
});

Deno.test("account deletion rejects a malformed authenticated user identifier", async () => {
  const backend = new DeleteAccountBackendSpy();
  backend.authenticatedID = "../not-a-user";
  const failures: DeleteAccountFailureEvent[] = [];

  const response = await handleDeleteAccountRequest(deletionRequest(), {
    backend,
    makeRequestID: () => requestID,
    logFailure: (event) => failures.push(event),
  });

  assertEquals(response.status, 503);
  assertFalse(backend.events.some((event) => event.startsWith("list:")));
  assertEquals(failures, [{ requestID, stage: "authentication" }]);
});

Deno.test("account deletion paginates photos, batches removal, then deletes atomically", async () => {
  const backend = new DeleteAccountBackendSpy();
  const firstPage = Array.from(
    { length: 1_000 },
    (_, index) => `photo-${String(index).padStart(4, "0")}.jpg`,
  );
  backend.listResult = (offset) => offset === 0 ? firstPage : ["profile.jpg"];

  const response = await handleDeleteAccountRequest(deletionRequest(), {
    backend,
    makeRequestID: () => requestID,
  });

  assertEquals(response.status, 200);
  assertEquals(await responseJSON(response), { deleted: true });
  assertEquals(response.headers.get("X-Request-ID"), requestID);
  assertEquals(backend.events.slice(0, 3), [
    "authenticate:header.payload.signature",
    "list:0:1000",
    "list:1000:1000",
  ]);
  assertEquals(backend.removedPaths.length, 11);
  assert(
    backend.removedPaths.slice(0, 10).every((batch) => batch.length === 100),
  );
  assertEquals(backend.removedPaths[10], [`${userID}/profile.jpg`]);
  assertEquals(backend.events.slice(-2), [
    `database:${userID}`,
    `auth_user:${userID}`,
  ]);
});

Deno.test("account deletion stops before database mutation when photo cleanup fails", async () => {
  const backend = new DeleteAccountBackendSpy();
  backend.failure = "remove";
  backend.listResult = () => ["profile.jpg"];
  const failures: DeleteAccountFailureEvent[] = [];

  const response = await handleDeleteAccountRequest(deletionRequest(), {
    backend,
    makeRequestID: () => requestID,
    logFailure: (event) => failures.push(event),
  });

  assertEquals(response.status, 503);
  assertEquals(response.headers.get("Retry-After"), "60");
  assertFalse(backend.events.some((event) => event.startsWith("database:")));
  assertFalse(backend.events.some((event) => event.startsWith("auth_user:")));
  assertEquals(failures, [{ requestID, stage: "profile_photos" }]);
});

Deno.test("account deletion rejects unsafe storage object names", async () => {
  const backend = new DeleteAccountBackendSpy();
  backend.listResult = () => ["../outside.jpg"];
  const failures: DeleteAccountFailureEvent[] = [];

  const response = await handleDeleteAccountRequest(deletionRequest(), {
    backend,
    makeRequestID: () => requestID,
    logFailure: (event) => failures.push(event),
  });

  assertEquals(response.status, 503);
  assertFalse(backend.events.some((event) => event.startsWith("remove:")));
  assertEquals(failures, [{ requestID, stage: "profile_photos" }]);
});

Deno.test("account deletion caps the profile photo cleanup workload", async () => {
  const backend = new DeleteAccountBackendSpy();
  backend.listResult = (offset, limit) =>
    Array.from(
      { length: limit },
      (_, index) => `photo-${String(offset + index).padStart(5, "0")}.jpg`,
    );
  const failures: DeleteAccountFailureEvent[] = [];

  const response = await handleDeleteAccountRequest(deletionRequest(), {
    backend,
    makeRequestID: () => requestID,
    logFailure: (event) => failures.push(event),
  });

  assertEquals(response.status, 503);
  assertFalse(backend.events.some((event) => event.startsWith("remove:")));
  assertFalse(backend.events.some((event) => event.startsWith("database:")));
  assertEquals(failures, [{ requestID, stage: "profile_photos" }]);
});

Deno.test("account deletion leaves Auth intact when database preparation fails", async () => {
  const backend = new DeleteAccountBackendSpy();
  backend.failure = "database";
  const failures: DeleteAccountFailureEvent[] = [];

  const response = await handleDeleteAccountRequest(deletionRequest(), {
    backend,
    makeRequestID: () => requestID,
    logFailure: (event) => failures.push(event),
  });

  assertEquals(response.status, 503);
  assertFalse(backend.events.some((event) => event.startsWith("auth_user:")));
  assertEquals(failures, [{ requestID, stage: "database" }]);
});

Deno.test("account deletion reports only the failed Auth stage after preparation", async () => {
  const backend = new DeleteAccountBackendSpy();
  backend.failure = "auth_user";
  const failures: DeleteAccountFailureEvent[] = [];

  const response = await handleDeleteAccountRequest(deletionRequest(), {
    backend,
    makeRequestID: () => requestID,
    logFailure: (event) => failures.push(event),
  });

  assertEquals(response.status, 503);
  assert(backend.events.includes(`database:${userID}`));
  assertEquals(failures, [{ requestID, stage: "auth_user" }]);
});

class RevocationSpy {
  calls: string[] = [];
  result: AppleRevocationResult = { revoked: true };
  constructor(private readonly events: string[]) {}

  revoke = (authorizationCode: string): Promise<AppleRevocationResult> => {
    this.calls.push(authorizationCode);
    this.events.push("revoke");
    return Promise.resolve(this.result);
  };
}

Deno.test("account deletion accepts exactly the three request shapes", () => {
  assertEquals(parseDeleteAccountBody({ confirmation: "delete" }), {
    mode: "self",
  });
  assertEquals(
    parseDeleteAccountBody({
      confirmation: "delete",
      apple_authorization_code: appleCode,
    }),
    { mode: "self", appleAuthorizationCode: appleCode },
  );
  assertEquals(
    parseDeleteAccountBody({ confirmation: "delete", member_id: wardMemberID }),
    { mode: "guardian", memberID: wardMemberID },
  );

  for (
    const payload of [
      { confirmation: "delete", apple_authorization_code: null },
      { confirmation: "delete", apple_authorization_code: "" },
      { confirmation: "delete", apple_authorization_code: "has space" },
      { confirmation: "delete", apple_authorization_code: "a".repeat(513) },
      { confirmation: "delete", member_id: wardMemberID.toUpperCase() },
      { confirmation: "delete", member_id: null },
      {
        confirmation: "delete",
        member_id: wardMemberID,
        apple_authorization_code: appleCode,
      },
      { confirmation: "remove", member_id: wardMemberID },
      { apple_authorization_code: appleCode },
    ]
  ) {
    assertEquals(
      parseDeleteAccountBody(payload),
      null,
      JSON.stringify(payload),
    );
  }
});

Deno.test("the Apple token is revoked only after the Auth user is deleted", async () => {
  const backend = new DeleteAccountBackendSpy();
  const revocation = new RevocationSpy(backend.events);

  const response = await handleDeleteAccountRequest(
    deletionRequest(JSON.stringify({
      confirmation: "delete",
      apple_authorization_code: appleCode,
    })),
    { backend, revokeAppleToken: revocation.revoke },
  );

  assertEquals(response.status, 200);
  assertEquals(await responseJSON(response), { deleted: true });
  assertEquals(revocation.calls, [appleCode]);
  assertEquals(backend.events.slice(-3), [
    `database:${userID}`,
    `auth_user:${userID}`,
    "revoke",
  ]);
});

Deno.test("a deletion that fails never revokes the Apple token", async () => {
  for (const failure of ["remove", "database", "auth_user"] as const) {
    const backend = new DeleteAccountBackendSpy();
    backend.failure = failure;
    backend.listResult = () => ["profile.jpg"];
    const revocation = new RevocationSpy(backend.events);

    const response = await handleDeleteAccountRequest(
      deletionRequest(JSON.stringify({
        confirmation: "delete",
        apple_authorization_code: appleCode,
      })),
      { backend, revokeAppleToken: revocation.revoke },
    );

    assertEquals(response.status, 503);
    assertEquals(revocation.calls, [], failure);
  }
});

Deno.test("a failed revocation still reports the deletion and logs only its stage", async () => {
  const backend = new DeleteAccountBackendSpy();
  const revocation = new RevocationSpy(backend.events);
  revocation.result = { revoked: false, stage: "token_exchange" };
  const revocationFailures: AppleTokenRevocationFailureEvent[] = [];
  const deletionFailures: DeleteAccountFailureEvent[] = [];

  const response = await handleDeleteAccountRequest(
    deletionRequest(JSON.stringify({
      confirmation: "delete",
      apple_authorization_code: appleCode,
    })),
    {
      backend,
      revokeAppleToken: revocation.revoke,
      makeRequestID: () => requestID,
      logFailure: (event) => deletionFailures.push(event),
      logRevocationFailure: (event) => revocationFailures.push(event),
    },
  );

  assertEquals(response.status, 200);
  assertEquals(await responseJSON(response), { deleted: true });
  assertEquals(revocationFailures, [{ requestID, stage: "token_exchange" }]);
  assertEquals(deletionFailures, []);
  assertFalse(JSON.stringify(revocationFailures).includes(appleCode));
  assertFalse(JSON.stringify(revocationFailures).includes(userID));
});

Deno.test("a revoker that throws still leaves the deletion reported as done", async () => {
  const backend = new DeleteAccountBackendSpy();
  const revocationFailures: AppleTokenRevocationFailureEvent[] = [];

  const response = await handleDeleteAccountRequest(
    deletionRequest(JSON.stringify({
      confirmation: "delete",
      apple_authorization_code: appleCode,
    })),
    {
      backend,
      revokeAppleToken: () => Promise.reject(new Error("boom")),
      makeRequestID: () => requestID,
      logRevocationFailure: (event) => revocationFailures.push(event),
    },
  );

  assertEquals(response.status, 200);
  assertEquals(revocationFailures, [{ requestID, stage: "revoke" }]);
});

Deno.test("a deletion without an Apple code never calls the revoker", async () => {
  const backend = new DeleteAccountBackendSpy();
  const revocation = new RevocationSpy(backend.events);

  const response = await handleDeleteAccountRequest(deletionRequest(), {
    backend,
    revokeAppleToken: revocation.revoke,
  });

  assertEquals(response.status, 200);
  assertEquals(revocation.calls, []);
});

Deno.test("a guardian deletion stops before any database mutation when the caller is not the ward's live guardian", async () => {
  const backend = new DeleteAccountBackendSpy();
  backend.guardianWard = null;
  const revocation = new RevocationSpy(backend.events);

  const response = await handleDeleteAccountRequest(
    deletionRequest(JSON.stringify({
      confirmation: "delete",
      member_id: wardMemberID,
    })),
    { backend, revokeAppleToken: revocation.revoke },
  );

  assertEquals(response.status, 403);
  assertEquals(await responseJSON(response), {
    error: "guardian_access_denied",
  });
  assertEquals(backend.events, [
    "authenticate:header.payload.signature",
    `guardian:${userID}:${wardMemberID}`,
  ]);
  assertEquals(revocation.calls, []);
});

Deno.test("a guardian deletion removes the ward's account in the same order and never the guardian's", async () => {
  const backend = new DeleteAccountBackendSpy();
  backend.listResult = () => ["profile.jpg"];
  const revocation = new RevocationSpy(backend.events);

  const response = await handleDeleteAccountRequest(
    deletionRequest(JSON.stringify({
      confirmation: "delete",
      member_id: wardMemberID,
    })),
    { backend, revokeAppleToken: revocation.revoke },
  );

  assertEquals(response.status, 200);
  assertEquals(backend.removedPaths, [[`${wardID}/profile.jpg`]]);
  assertEquals(backend.events.slice(-2), [
    `database:${wardID}`,
    `auth_user:${wardID}`,
  ]);
  assertFalse(
    backend.events.some((event) =>
      event.endsWith(userID) && event.startsWith("database:")
    ),
  );
  assertEquals(revocation.calls, []);
});

Deno.test("an unavailable guardian check fails closed before touching the ward", async () => {
  const backend = new DeleteAccountBackendSpy();
  backend.failure = "guardian";
  const failures: DeleteAccountFailureEvent[] = [];

  const response = await handleDeleteAccountRequest(
    deletionRequest(JSON.stringify({
      confirmation: "delete",
      member_id: wardMemberID,
    })),
    {
      backend,
      makeRequestID: () => requestID,
      logFailure: (event) => failures.push(event),
    },
  );

  assertEquals(response.status, 503);
  assertFalse(backend.events.some((event) => event.startsWith("list:")));
  assertEquals(failures, [{ requestID, stage: "guardian_authorization" }]);
});

Deno.test("a signed-in person with no house is deleted without any household lookup", async () => {
  const backend = new DeleteAccountBackendSpy();

  const response = await handleDeleteAccountRequest(deletionRequest(), {
    backend,
  });

  assertEquals(response.status, 200);
  assertEquals(backend.events, [
    "authenticate:header.payload.signature",
    "list:0:1000",
    `database:${userID}`,
    `auth_user:${userID}`,
  ]);

  const shared = await Deno.readTextFile(
    new URL("./delete-account.ts", import.meta.url),
  );
  const endpoint = await Deno.readTextFile(
    new URL("../delete-account/index.ts", import.meta.url),
  );
  for (const source of [shared, endpoint]) {
    assertFalse(source.includes("family_members"));
    assertFalse(source.includes("get_current_home_context"));
    assertFalse(source.includes("active_family_id"));
  }
});

Deno.test("delete-account endpoint delegates to the shared transactional contract", async () => {
  const endpointSource = await Deno.readTextFile(
    new URL("../delete-account/index.ts", import.meta.url),
  );
  assert(endpointSource.includes("handleDeleteAccountRequest(request"));
  assert(endpointSource.includes('.rpc("prepare_account_deletion"'));
  assert(endpointSource.includes('"authorize_guardian_account_deletion"'));
  assert(endpointSource.includes('event: "apple_token_revocation_failed"'));
  assert(endpointSource.includes("revokeAppleSignIn(authorizationCode"));

  const logBodies = [...endpointSource.matchAll(
    /console\.(?:info|error)\(JSON\.stringify\(\{([\s\S]*?)\}\)\);/g,
  )].map((match) => match[1]);
  assertEquals(logBodies.length, 2);
  for (const logBody of logBodies) {
    assertFalse(logBody.includes("authorizationCode"));
    assertFalse(logBody.includes("userID"));
    assertFalse(logBody.includes("memberID"));
    assertFalse(logBody.includes("refresh_token"));
  }
  assertFalse(endpointSource.includes('.from("families")'));
  assertFalse(endpointSource.includes("reason: String(error)"));
  assertFalse(/\n\s*user_id:/.test(endpointSource));

  const clientSource = await Deno.readTextFile(
    new URL("../../../Nina/SupabaseAuthClient.swift", import.meta.url),
  );
  assert(clientSource.includes('let confirmation = "delete"'));
});

Deno.test("the app matches every delete-account error code whole", async () => {
  const contract = await Deno.readTextFile(
    new URL("./delete-account.ts", import.meta.url),
  );
  const client = await Deno.readTextFile(
    new URL("../../../Nina/SupabaseAuthClient.swift", import.meta.url),
  );
  const codes = new Set(
    [...contract.matchAll(/\{\s*error:\s*"([a-z_]+)"\s*\}/g)].map((match) =>
      match[1]
    ),
  );

  assert(codes.size >= 8);
  for (const code of codes) {
    assert(client.includes(`"${code}"`), `${code} is not matched by the app`);
  }
});

Deno.test("the app sends only the three bodies delete-account accepts", async () => {
  const contract = await Deno.readTextFile(
    new URL("./delete-account.ts", import.meta.url),
  );
  const client = await Deno.readTextFile(
    new URL("../../../Nina/SupabaseAuthClient.swift", import.meta.url),
  );
  const pattern = contract.match(
    /const appleAuthorizationCodePattern = \/(.+)\/;/,
  )?.[1];

  assert(pattern);
  assert(client.includes(`#"${pattern}"#`));
  assert(client.includes('let confirmation = "delete"'));
  assert(client.includes('"apple_authorization_code"'));
  assert(client.includes('"member_id"'));
  assert(client.includes("uuidString.lowercased()"));
});

Deno.test("maintenance deletes a minor account in the same order and stops at the first failure", async () => {
  const backend = new DeleteAccountBackendSpy();
  backend.listResult = () => ["profile.jpg"];
  assertEquals(await deleteAccountInOrder(backend, wardID), null);
  assertEquals(backend.events, [
    "list:0:1000",
    "remove:1",
    `database:${wardID}`,
    `auth_user:${wardID}`,
  ]);

  const failing = new DeleteAccountBackendSpy();
  failing.failure = "database";
  assertEquals(await deleteAccountInOrder(failing, wardID), "database");
  assertFalse(failing.events.some((event) => event.startsWith("auth_user:")));
  assertEquals(await deleteAccountInOrder(failing, "not-a-user"), "database");
});
