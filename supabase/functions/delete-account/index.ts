import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import {
  type DeleteAccountBackend,
  handleDeleteAccountRequest,
} from "../_shared/delete-account.ts";

const upstreamTimeoutMilliseconds = 8_000;

function parseConfiguredKey(variable: string, fallback: string): string {
  const configured = Deno.env.get(variable)?.trim();
  if (configured) {
    try {
      const parsed: unknown = JSON.parse(configured);
      if (
        typeof parsed === "object" && parsed !== null && !Array.isArray(parsed)
      ) {
        const keys = parsed as Record<string, unknown>;
        if (typeof keys.default === "string" && keys.default.trim()) {
          return keys.default.trim();
        }
        const first = Object.values(keys).find((value) =>
          typeof value === "string" && value.trim().length > 0
        );
        if (typeof first === "string") return first.trim();
      }
    } catch {
      return configured;
    }
  }
  return Deno.env.get(fallback)?.trim() ?? "";
}

function rootSupabaseURL(rawValue: string): string | null {
  try {
    const url = new URL(rawValue);
    const loopback = url.hostname === "localhost" ||
      url.hostname === "127.0.0.1" ||
      url.hostname === "::1";
    if (
      (url.protocol !== "https:" && !(loopback && url.protocol === "http:")) ||
      url.username || url.password || url.pathname !== "/" || url.search ||
      url.hash
    ) {
      return null;
    }
    return url.origin;
  } catch {
    return null;
  }
}

function legacyKeyRole(key: string): string | null {
  const payload = key.split(".")[1];
  if (!payload) return null;

  try {
    const base64 = payload.replaceAll("-", "+").replaceAll("_", "/")
      .padEnd(Math.ceil(payload.length / 4) * 4, "=");
    const decoded: unknown = JSON.parse(atob(base64));
    if (typeof decoded !== "object" || decoded === null) return null;
    const role = (decoded as Record<string, unknown>).role;
    return typeof role === "string" ? role : null;
  } catch {
    return null;
  }
}

function isServiceRoleKey(key: string): boolean {
  return /^sb_secret_[A-Za-z0-9._-]{16,}$/.test(key) ||
    legacyKeyRole(key) === "service_role";
}

const timedFetch: typeof fetch = (input, init = {}) =>
  fetch(input, {
    ...init,
    signal: init.signal ?? AbortSignal.timeout(upstreamTimeoutMilliseconds),
  });

class SupabaseDeleteAccountBackend implements DeleteAccountBackend {
  constructor(private readonly admin: SupabaseClient) {}

  async authenticatedUserID(accessToken: string): Promise<string | null> {
    const { data, error } = await this.admin.auth.getUser(accessToken);
    if (error) {
      const status = (error as { status?: number }).status;
      if (status === 400 || status === 401 || status === 403) return null;
      throw new Error("auth_lookup_failed");
    }
    return data.user?.id ?? null;
  }

  async listProfilePhotoNames(
    userID: string,
    offset: number,
    limit: number,
  ): Promise<string[]> {
    const { data, error } = await this.admin.storage
      .from("profile-photos")
      .list(userID, {
        limit,
        offset,
        sortBy: { column: "name", order: "asc" },
      });
    if (error) throw new Error("profile_photo_list_failed");
    return (data ?? []).map((file) => file.name);
  }

  async removeProfilePhotoPaths(paths: string[]): Promise<void> {
    const { error } = await this.admin.storage.from("profile-photos").remove(
      paths,
    );
    if (error) throw new Error("profile_photo_remove_failed");
  }

  async prepareAccountDeletion(userID: string): Promise<void> {
    const { data, error } = await this.admin.rpc("prepare_account_deletion", {
      target_user_id: userID,
    });
    const result = data as { prepared?: unknown } | null;
    if (error || result?.prepared !== true) {
      throw new Error("account_deletion_prepare_failed");
    }
  }

  async deleteAuthUser(userID: string): Promise<void> {
    const { error } = await this.admin.auth.admin.deleteUser(userID);
    if (error) throw new Error("auth_user_delete_failed");
  }
}

function configuredBackend(): DeleteAccountBackend | undefined {
  const supabaseURL = rootSupabaseURL(
    Deno.env.get("SUPABASE_URL")?.trim() ?? "",
  );
  const serviceRoleKey = parseConfiguredKey(
    "SUPABASE_SECRET_KEYS",
    "SUPABASE_SERVICE_ROLE_KEY",
  );
  if (!supabaseURL || !isServiceRoleKey(serviceRoleKey)) return undefined;

  const admin = createClient(supabaseURL, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
    global: { fetch: timedFetch },
  });
  return new SupabaseDeleteAccountBackend(admin);
}

Deno.serve((request: Request) =>
  handleDeleteAccountRequest(request, {
    backend: configuredBackend(),
    logFailure: ({ requestID, stage }) => {
      console.error(JSON.stringify({
        event: "delete_account_failed",
        request_id: requestID,
        stage,
      }));
    },
  })
);
