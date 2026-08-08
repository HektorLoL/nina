export const deleteAccountConfirmation = "delete";
export const maxDeleteAccountRequestBytes = 1_024;

const maxAuthorizationBytes = 8_192;
const profilePhotoPageSize = 1_000;
const profilePhotoRemovalBatchSize = 100;
const maxProfilePhotoCount = 10_000;

export type DeleteAccountFailureStage =
  | "configuration"
  | "authentication"
  | "profile_photos"
  | "database"
  | "auth_user";

export type DeleteAccountFailureEvent = {
  requestID: string;
  stage: DeleteAccountFailureStage;
};

export interface DeleteAccountBackend {
  authenticatedUserID(accessToken: string): Promise<string | null>;
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
  makeRequestID?: () => string;
  logFailure?: (event: DeleteAccountFailureEvent) => void;
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
  | { ok: true }
  | { ok: false; response: Response };

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

  if (
    typeof payload !== "object" || payload === null || Array.isArray(payload)
  ) {
    return {
      ok: false,
      response: jsonResponse(
        requestID,
        { error: "confirmation_required" },
        400,
      ),
    };
  }

  const keys = Object.keys(payload);
  if (
    keys.length !== 1 || keys[0] !== "confirmation" ||
    (payload as Record<string, unknown>).confirmation !==
      deleteAccountConfirmation
  ) {
    return {
      ok: false,
      response: jsonResponse(
        requestID,
        { error: "confirmation_required" },
        400,
      ),
    };
  }

  return { ok: true };
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

async function deleteProfilePhotos(
  backend: DeleteAccountBackend,
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

  let userID: string | null;
  try {
    userID = await backend.authenticatedUserID(accessToken);
  } catch {
    reportFailure(dependencies, requestID, "authentication");
    return failureResponse(requestID);
  }

  if (!userID) {
    return jsonResponse(requestID, { error: "not_authenticated" }, 401);
  }
  if (!isUUID(userID)) {
    reportFailure(dependencies, requestID, "authentication");
    return failureResponse(requestID);
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

  return jsonResponse(requestID, { deleted: true });
}
