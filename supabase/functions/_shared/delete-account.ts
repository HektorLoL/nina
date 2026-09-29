import type { AppleRevocationResult } from "./apple-sign-in-revocation.ts";

export const deleteAccountConfirmation = "delete";
export const maxDeleteAccountRequestBytes = 1_024;

const maxAuthorizationBytes = 8_192;
const profilePhotoPageSize = 1_000;
const profilePhotoRemovalBatchSize = 100;
const maxProfilePhotoCount = 10_000;

const appleAuthorizationCodePattern = /^[A-Za-z0-9._-]{1,512}$/;
const lowercaseUUIDPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

export type DeleteAccountFailureStage =
  | "configuration"
  | "authentication"
  | "guardian_authorization"
  | "profile_photos"
  | "database"
  | "auth_user";

export type DeleteAccountFailureEvent = {
  requestID: string;
  stage: DeleteAccountFailureStage;
};

export type AppleTokenRevocationFailureEvent = {
  requestID: string;
  stage: "configuration" | "token_exchange" | "revoke";
};

export type DeleteAccountRequestBody =
  | { mode: "self"; appleAuthorizationCode?: string }
  | { mode: "guardian"; memberID: string };

export interface DeleteAccountBackend {
  authenticatedUserID(accessToken: string): Promise<string | null>;
  // Null means the caller is not a live guardian of that claimed minor.
  authorizeGuardianAccountDeletion(
    guardianUserID: string,
    memberID: string,
  ): Promise<string | null>;
  listProfilePhotoNames(
    userID: string,
    offset: number,
    limit: number,
  ): Promise<string[]>;
  removeProfilePhotoPaths(paths: string[]): Promise<void>;
  prepareAccountDeletion(userID: string): Promise<void>;
  deleteAuthUser(userID: string): Promise<void>;
}

export type DeleteAccountDependencies = {
  backend?: DeleteAccountBackend;
  revokeAppleToken?: (
    authorizationCode: string,
  ) => Promise<AppleRevocationResult>;
  makeRequestID?: () => string;
  logFailure?: (event: DeleteAccountFailureEvent) => void;
  logRevocationFailure?: (event: AppleTokenRevocationFailureEvent) => void;
};

function responseHeaders(
  requestID: string,
  extra: HeadersInit = {},
): Headers {
  const headers = new Headers(extra);
  headers.set("Cache-Control", "no-store");
  headers.set("X-Content-Type-Options", "nosniff");
  headers.set("X-Request-ID", requestID);
  return headers;
}

function jsonResponse(
  requestID: string,
  body: unknown,
  status = 200,
  headers: HeadersInit = {},
): Response {
  return Response.json(body, {
    status,
    headers: responseHeaders(requestID, headers),
  });
}

function failureResponse(requestID: string): Response {
  return jsonResponse(
    requestID,
    { error: "delete_account_failed" },
    503,
    { "Retry-After": "60" },
  );
}

function reportFailure(
  dependencies: DeleteAccountDependencies,
  requestID: string,
  stage: DeleteAccountFailureStage,
) {
  try {
    dependencies.logFailure?.({ requestID, stage });
  } catch {
    // Logging must never change deletion behavior or expose the underlying error.
  }
}

function bearerToken(request: Request): string | null {
  const authorization = request.headers.get("Authorization");
  if (!authorization || authorization.length > maxAuthorizationBytes) {
    return null;
  }

  const match = /^Bearer ([^\s]+)$/.exec(authorization);
  return match?.[1] ?? null;
}

function isUUID(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
    .test(value);
}

async function readBoundedBody(request: Request): Promise<string | null> {
  const declaredLength = request.headers.get("Content-Length");
  if (declaredLength !== null) {
    const parsedLength = Number(declaredLength);
    if (
      !Number.isSafeInteger(parsedLength) || parsedLength < 0 ||
      parsedLength > maxDeleteAccountRequestBytes
    ) {
      return null;
    }
  }

  if (!request.body) return "";

  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maxDeleteAccountRequestBytes) {
      await reader.cancel().catch(() => undefined);
      return null;
    }
    chunks.push(value);
  }

  const body = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    body.set(chunk, offset);
    offset += chunk.byteLength;
  }

  try {
    return new TextDecoder("utf-8", { fatal: true }).decode(body);
  } catch {
    return "\u0000";
  }
}

type ConfirmationResult =
  | { ok: true; body: DeleteAccountRequestBody }
  | { ok: false; response: Response };

export function parseDeleteAccountBody(
  payload: unknown,
): DeleteAccountRequestBody | null {
  if (
    typeof payload !== "object" || payload === null || Array.isArray(payload)
  ) {
    return null;
  }

  const record = payload as Record<string, unknown>;
  const keys = Object.keys(record).sort();
  if (record.confirmation !== deleteAccountConfirmation) return null;

  if (keys.length === 1 && keys[0] === "confirmation") {
    return { mode: "self" };
  }

  if (
    keys.length === 2 &&
    keys[0] === "apple_authorization_code" &&
    keys[1] === "confirmation" &&
    typeof record.apple_authorization_code === "string" &&
    appleAuthorizationCodePattern.test(record.apple_authorization_code)
  ) {
    return {
      mode: "self",
      appleAuthorizationCode: record.apple_authorization_code,
    };
  }

  if (
    keys.length === 2 &&
    keys[0] === "confirmation" &&
    keys[1] === "member_id" &&
    typeof record.member_id === "string" &&
    lowercaseUUIDPattern.test(record.member_id)
  ) {
    return { mode: "guardian", memberID: record.member_id };
  }

  return null;
}

async function requireConfirmation(
  request: Request,
  requestID: string,
): Promise<ConfirmationResult> {
  const contentType = request.headers.get("Content-Type")
    ?.split(";", 1)[0]
    .trim()
    .toLowerCase();
  if (contentType !== "application/json") {
    return {
      ok: false,
      response: jsonResponse(
        requestID,
        { error: "unsupported_media_type" },
        415,
      ),
    };
  }

  const body = await readBoundedBody(request);
  if (body === null) {
    return {
      ok: false,
      response: jsonResponse(requestID, { error: "payload_too_large" }, 413),
    };
  }

  let payload: unknown;
  try {
    payload = JSON.parse(body);
  } catch {
    return {
      ok: false,
      response: jsonResponse(requestID, { error: "invalid_request" }, 400),
    };
  }

  const parsed = parseDeleteAccountBody(payload);
  if (!parsed) {
    return {
      ok: false,
      response: jsonResponse(
        requestID,
        { error: "confirmation_required" },
        400,
      ),
    };
  }

  return { ok: true, body: parsed };
}

function isSafeProfilePhotoName(name: unknown): name is string {
  if (
    typeof name !== "string" || name.length === 0 || name.length > 255 ||
    name === "." || name === ".." || name.includes("/") || name.includes("\\")
  ) {
    return false;
  }

  for (const character of name) {
    const codePoint = character.codePointAt(0) ?? 0;
    if (codePoint <= 31 || codePoint === 127) return false;
  }
  return true;
}

export type ProfilePhotoStore = Pick<
  DeleteAccountBackend,
  "listProfilePhotoNames" | "removeProfilePhotoPaths"
>;

export async function deleteProfilePhotos(
  backend: ProfilePhotoStore,
  userID: string,
) {
  const names: string[] = [];
  const uniqueNames = new Set<string>();
  let offset = 0;

  while (true) {
    const page = await backend.listProfilePhotoNames(
      userID,
      offset,
      profilePhotoPageSize,
    );
    if (!Array.isArray(page) || page.length > profilePhotoPageSize) {
      throw new Error("invalid_profile_photo_page");
    }

    for (const name of page) {
      if (!isSafeProfilePhotoName(name) || uniqueNames.has(name)) {
        throw new Error("invalid_profile_photo_name");
      }
      uniqueNames.add(name);
      names.push(name);
      if (names.length > maxProfilePhotoCount) {
        throw new Error("profile_photo_limit_exceeded");
      }
    }

    if (page.length < profilePhotoPageSize) break;
    offset += page.length;
  }

  for (
    let index = 0;
    index < names.length;
    index += profilePhotoRemovalBatchSize
  ) {
    const paths = names
      .slice(index, index + profilePhotoRemovalBatchSize)
      .map((name) => `${userID}/${name}`);
    await backend.removeProfilePhotoPaths(paths);
  }
}

export async function handleDeleteAccountRequest(
  request: Request,
  dependencies: DeleteAccountDependencies,
): Promise<Response> {
  const requestID = dependencies.makeRequestID?.() ?? crypto.randomUUID();

  if (request.method !== "POST") {
    return jsonResponse(
      requestID,
      { error: "method_not_allowed" },
      405,
      { Allow: "POST" },
    );
  }

  const confirmation = await requireConfirmation(request, requestID);
  if (!confirmation.ok) return confirmation.response;

  const accessToken = bearerToken(request);
  if (!accessToken) {
    return jsonResponse(requestID, { error: "not_authenticated" }, 401);
  }

  const backend = dependencies.backend;
  if (!backend) {
    reportFailure(dependencies, requestID, "configuration");
    return jsonResponse(
      requestID,
      { error: "service_not_configured" },
      503,
      { "Retry-After": "60" },
    );
  }

  let callerID: string | null;
  try {
    callerID = await backend.authenticatedUserID(accessToken);
  } catch {
    reportFailure(dependencies, requestID, "authentication");
    return failureResponse(requestID);
  }

  if (!callerID) {
    return jsonResponse(requestID, { error: "not_authenticated" }, 401);
  }
  if (!isUUID(callerID)) {
    reportFailure(dependencies, requestID, "authentication");
    return failureResponse(requestID);
  }

  const body = confirmation.body;
  let userID = callerID;
  if (body.mode === "guardian") {
    let wardID: string | null;
    try {
      wardID = await backend.authorizeGuardianAccountDeletion(
        callerID,
        body.memberID,
      );
    } catch {
      reportFailure(dependencies, requestID, "guardian_authorization");
      return failureResponse(requestID);
    }
    if (!wardID) {
      return jsonResponse(requestID, { error: "guardian_access_denied" }, 403);
    }
    if (!isUUID(wardID) || wardID === callerID) {
      reportFailure(dependencies, requestID, "guardian_authorization");
      return failureResponse(requestID);
    }
    userID = wardID;
  }

  try {
    await deleteProfilePhotos(backend, userID);
  } catch {
    reportFailure(dependencies, requestID, "profile_photos");
    return failureResponse(requestID);
  }

  try {
    await backend.prepareAccountDeletion(userID);
  } catch {
    reportFailure(dependencies, requestID, "database");
    return failureResponse(requestID);
  }

  try {
    await backend.deleteAuthUser(userID);
  } catch {
    reportFailure(dependencies, requestID, "auth_user");
    return failureResponse(requestID);
  }

  // The Apple token is revoked only after the account is gone, so revocation
  // can never block, undo or change the answer to a deletion.
  if (body.mode === "self" && body.appleAuthorizationCode) {
    await revokeAfterDeletion(
      dependencies,
      requestID,
      body.appleAuthorizationCode,
    );
  }

  return jsonResponse(requestID, { deleted: true });
}

async function revokeAfterDeletion(
  dependencies: DeleteAccountDependencies,
  requestID: string,
  authorizationCode: string,
) {
  let result: AppleRevocationResult;
  try {
    result = dependencies.revokeAppleToken
      ? await dependencies.revokeAppleToken(authorizationCode)
      : { revoked: false, stage: "configuration" };
  } catch {
    result = { revoked: false, stage: "revoke" };
  }
  if (result.revoked) return;

  try {
    dependencies.logRevocationFailure?.({ requestID, stage: result.stage });
  } catch {
    // Logging must never change deletion behavior or expose the underlying error.
  }
}

export type AccountDeletionStages = Pick<
  DeleteAccountBackend,
  | "listProfilePhotoNames"
  | "removeProfilePhotoPaths"
  | "prepareAccountDeletion"
  | "deleteAuthUser"
>;

// Every deletion path, a person's own, a guardian's or maintenance's, runs
// photos, then the database, then Auth, and stops at the first failure.
export async function deleteAccountInOrder(
  backend: AccountDeletionStages,
  userID: string,
): Promise<"profile_photos" | "database" | "auth_user" | null> {
  if (!isUUID(userID)) return "database";
  try {
    await deleteProfilePhotos(backend, userID);
  } catch {
    return "profile_photos";
  }
  try {
    await backend.prepareAccountDeletion(userID);
  } catch {
    return "database";
  }
  try {
    await backend.deleteAuthUser(userID);
  } catch {
    return "auth_user";
  }
  return null;
}
