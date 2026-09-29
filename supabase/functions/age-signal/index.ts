// deno-lint-ignore no-import-prefix
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import type { MappedAge } from "../_shared/age-assurance.ts";
import {
  type AgeSignalBackend,
  AgeSignalRateLimited,
  AgeSignalRejected,
  type AppAttestEnvironment,
  handleAgeSignalRequest,
  type RecordedAgeSignal,
  resolveAppAttestMode,
  rootCertificatesFrom,
  type StoredAttestKey,
} from "../_shared/app-attest.ts";
import { deleteProfilePhotos } from "../_shared/delete-account.ts";

const upstreamTimeoutMilliseconds = 8_000;

function parseConfiguredKey(variable: string, fallback: string): string {
  const configured = Deno.env.get(variable)?.trim();
  if (configured) {
    try {
      const parsed = JSON.parse(configured) as Record<string, unknown>;
      if (typeof parsed.default === "string" && parsed.default.trim()) {
        return parsed.default.trim();
      }
      const first = Object.values(parsed).find((value) =>
        typeof value === "string" && value.trim().length > 0
      );
      if (typeof first === "string") return first.trim();
    } catch {
      return configured;
    }
  }
  return Deno.env.get(fallback)?.trim() ?? "";
}

const timedFetch: typeof fetch = (input, init = {}) =>
  fetch(input, {
    ...init,
    signal: init.signal ?? AbortSignal.timeout(upstreamTimeoutMilliseconds),
  });

class SupabaseAgeSignalBackend implements AgeSignalBackend {
  constructor(
    private readonly admin: SupabaseClient,
    private readonly supabaseURL: string,
    private readonly publishableKey: string,
  ) {}

  async authenticatedUserID(accessToken: string): Promise<string | null> {
    const { data, error } = await this.admin.auth.getUser(accessToken);
    if (error) {
      const status = (error as { status?: number }).status;
      if (status === 400 || status === 401 || status === 403) return null;
      throw new Error("auth_lookup_failed");
    }
    return data.user?.id ?? null;
  }

  async issueChallenge(
    userID: string,
  ): Promise<{ challenge: string; expires_at: string }> {
    const { data, error } = await this.admin.rpc("issue_age_signal_challenge", {
      target_user_id: userID,
    });
    if (error) {
      if (error.message === "rate_limited") throw new AgeSignalRateLimited();
      throw new Error("challenge_unavailable");
    }
    const issued = data as { challenge?: unknown; expires_at?: unknown };
    if (
      typeof issued?.challenge !== "string" ||
      typeof issued?.expires_at !== "string"
    ) {
      throw new Error("challenge_unavailable");
    }
    return { challenge: issued.challenge, expires_at: issued.expires_at };
  }

  async consumeChallenge(userID: string, challenge: string): Promise<boolean> {
    const { data, error } = await this.admin.rpc(
      "consume_age_signal_challenge",
      { target_user_id: userID, challenge },
    );
    if (error) throw new Error("challenge_unavailable");
    return data === true;
  }

  async registerKey(
    userID: string,
    keyID: string,
    publicKeySPKI: string,
    environment: AppAttestEnvironment,
  ): Promise<void> {
    const { error } = await this.admin.rpc("register_app_attest_key", {
      target_user_id: userID,
      attest_key_id: keyID,
      public_key_spki: publicKeySPKI,
      attest_environment: environment,
    });
    if (error) throw new Error("register_failed");
  }

  async getKey(userID: string, keyID: string): Promise<StoredAttestKey | null> {
    const { data, error } = await this.admin.rpc("get_app_attest_key", {
      target_user_id: userID,
      attest_key_id: keyID,
    });
    if (error) throw new Error("key_lookup_failed");
    const key = data as Partial<StoredAttestKey> | null;
    if (
      !key || typeof key.public_key_spki !== "string" ||
      typeof key.counter !== "number" ||
      (key.environment !== "production" && key.environment !== "development")
    ) {
      return null;
    }
    return key as StoredAttestKey;
  }

  async advanceCounter(keyID: string, counter: number): Promise<boolean> {
    const { data, error } = await this.admin.rpc("advance_app_attest_counter", {
      attest_key_id: keyID,
      new_counter: counter,
    });
    if (error) throw new Error("counter_unavailable");
    return data === true;
  }

  async recordAgeSignal(
    userID: string,
    age: MappedAge,
  ): Promise<RecordedAgeSignal> {
    const { data, error } = await this.admin.rpc("record_age_signal", {
      target_user_id: userID,
      signal_status: age.status,
      signal_band: age.band,
      signal_assurance: age.assurance,
      signal_parental_controls: age.parentalControlsActive,
    });
    if (error) {
      if (error.message === "age_signal_rejected") {
        throw new AgeSignalRejected();
      }
      throw new Error("record_failed");
    }
    const recorded = data as Partial<RecordedAgeSignal> | null;
    if (!recorded || typeof recorded.status !== "string") {
      throw new Error("record_failed");
    }
    return {
      status: recorded.status,
      band: typeof recorded.band === "string" ? recorded.band : null,
      changed: recorded.changed === true,
      photo_cleanup_required: recorded.photo_cleanup_required === true,
    };
  }

  async deleteProfilePhotos(userID: string): Promise<void> {
    await deleteProfilePhotos({
      listProfilePhotoNames: async (owner, offset, limit) => {
        const { data, error } = await this.admin.storage
          .from("profile-photos")
          .list(owner, {
            limit,
            offset,
            sortBy: { column: "name", order: "asc" },
          });
        if (error) throw new Error("profile_photo_list_failed");
        return (data ?? []).map((file) => file.name);
      },
      removeProfilePhotoPaths: async (paths) => {
        const { error } = await this.admin.storage.from("profile-photos")
          .remove(paths);
        if (error) throw new Error("profile_photo_remove_failed");
      },
    }, userID);
  }

  async ageStatus(accessToken: string): Promise<unknown> {
    const userClient = createClient(this.supabaseURL, this.publishableKey, {
      global: {
        headers: { Authorization: `Bearer ${accessToken}` },
        fetch: timedFetch,
      },
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { data, error } = await userClient.rpc("get_my_age_status");
    if (error) throw new Error("status_unavailable");
    return data;
  }
}

function configuredBackend(): AgeSignalBackend | undefined {
  const supabaseURL = Deno.env.get("SUPABASE_URL")?.trim() ?? "";
  const publishableKey = parseConfiguredKey(
    "SUPABASE_PUBLISHABLE_KEYS",
    "SUPABASE_ANON_KEY",
  );
  const secretKey = parseConfiguredKey(
    "SUPABASE_SECRET_KEYS",
    "SUPABASE_SERVICE_ROLE_KEY",
  );
  if (!supabaseURL || !publishableKey || !secretKey) return undefined;

  const admin = createClient(supabaseURL, secretKey, {
    auth: { autoRefreshToken: false, persistSession: false },
    global: { fetch: timedFetch },
  });
  return new SupabaseAgeSignalBackend(admin, supabaseURL, publishableKey);
}

Deno.serve((request: Request) => {
  const supabaseURL = Deno.env.get("SUPABASE_URL")?.trim() ?? "";
  let rootCertificates;
  try {
    rootCertificates = rootCertificatesFrom(
      Deno.env.get("APPLE_APP_ATTEST_ROOT_CA_PEM"),
    );
  } catch {
    rootCertificates = undefined;
  }

  return handleAgeSignalRequest(request, {
    mode: rootCertificates
      ? resolveAppAttestMode(Deno.env.get("NINA_APP_ATTEST_MODE"), supabaseURL)
      : null,
    backend: configuredBackend(),
    rootCertificates,
    logRecorded: ({ changed, eligibleForAgeFeatures }) => {
      console.info(JSON.stringify({
        event: "age_signal_recorded",
        changed,
        eligible_for_age_features: eligibleForAgeFeatures,
      }));
    },
    logFailure: ({ stage }) => {
      console.error(JSON.stringify({
        event: "age_signal_failed",
        stage,
      }));
    },
  });
});
