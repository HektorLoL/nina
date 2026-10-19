import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2";
import {
  type AccountDeletionStages,
  deleteAccountInOrder,
} from "../_shared/delete-account.ts";
import { isRosterEntry, Pseudonymizer } from "../_shared/nina-pseudonyms.ts";
import {
  addUsage,
  calculateActualCostMicrousd,
  emptyUsage,
  environmentPricing,
  estimateInsightReservationMicrousd,
  extractOutputText,
  insightFallbackModel,
  insightModel,
  insightResponseSchema,
  isSafetySalt,
  maxInputTokens,
  maxInsightOutputTokens,
  type OpenAIResponsePayload,
  pricingForModel,
  pricingVersion,
  safetyIdentifier,
  shouldUseInsightFallback,
  usageFromResponse,
} from "../_shared/nina-ai.ts";
import {
  failureCode,
  insightTexts,
  moderate,
  moderationTexts,
  NinaFailure,
  type OpenAIAnswer,
  postOpenAI,
  upstreamFailure,
  upstreamStatus,
} from "../_shared/nina-openai.ts";

type WeeklyCandidate = {
  family_id: string;
  period_start: string;
  period_end: string;
  relevant_event_count: number;
  tasks_created: number;
  tasks_completed: number;
  tasks_open: number;
  open_tasks_by_owner: Record<string, number>;
  shopping_events: number;
  reminder_events: number;
  shared_memory_events: number;
};

const insightInstructions = `
Você escreve insights semanais curtos para uma família.
- Use somente as métricas determinísticas fornecidas.
- Nomes como Criança 1, Adolescente 1, Pessoa 1 ou Adulto 1 são pessoas da casa. Use-os exatamente assim e não tente descobrir quem são.
- Não atribua culpa, intenção, saúde mental ou valor moral.
- Não invente eventos, pessoas ou causas.
- Destaque progresso, pendências e desequilíbrios observáveis com linguagem gentil.
- Produza de um a quatro insights em português do Brasil.
`.trim();

function jsonResponse(body: unknown, status = 200): Response {
  return Response.json(body, {
    status,
    headers: { "Cache-Control": "no-store" },
  });
}

function parseConfiguredKey(variable: string, fallback: string): string {
  const configured = Deno.env.get(variable);
  if (configured) {
    try {
      const parsed = JSON.parse(configured) as Record<string, string>;
      if (parsed.default) return parsed.default;
      const first = Object.values(parsed).find(Boolean);
      if (first) return first;
    } catch {
      if (configured.length > 20) return configured;
    }
  }
  return Deno.env.get(fallback) ?? "";
}

function accountDeletionStages(admin: SupabaseClient): AccountDeletionStages {
  return {
    listProfilePhotoNames: async (userID, offset, limit) => {
      const { data, error } = await admin.storage
        .from("profile-photos")
        .list(userID, {
          limit,
          offset,
          sortBy: { column: "name", order: "asc" },
        });
      if (error) throw new Error("profile_photo_list_failed");
      return (data ?? []).map((file) => file.name);
    },
    removeProfilePhotoPaths: async (paths) => {
      const { error } = await admin.storage.from("profile-photos").remove(paths);
      if (error) throw new Error("profile_photo_remove_failed");
    },
    prepareAccountDeletion: async (userID) => {
      const { data, error } = await admin.rpc("prepare_account_deletion", {
        target_user_id: userID,
      });
      if (error || (data as { prepared?: unknown } | null)?.prepared !== true) {
        throw new Error("account_deletion_prepare_failed");
      }
    },
    deleteAuthUser: async (userID) => {
      const { error } = await admin.auth.admin.deleteUser(userID);
      if (error) throw new Error("auth_user_delete_failed");
    },
  };
}

// A minor's account does not outlive its house: after thirty days without one
// it is deleted in the order a person's own deletion follows.
async function deleteMinorAccountsWithoutAHouse(
  admin: SupabaseClient,
): Promise<{ deleted: number; failed: number }> {
  const { data, error } = await admin.rpc(
    "list_minor_accounts_due_for_deletion",
    { max_accounts: 25 },
  );
  if (error) {
    console.error(JSON.stringify({
      event: "minor_account_deletion_failed",
      stage: "list",
    }));
    return { deleted: 0, failed: 1 };
  }

  const stages = accountDeletionStages(admin);
  let deleted = 0;
  let failed = 0;
  for (const accountID of Array.isArray(data) ? data : []) {
    const failure = typeof accountID === "string"
      ? await deleteAccountInOrder(stages, accountID)
      : "database";
    if (failure) {
      failed += 1;
      console.error(JSON.stringify({
        event: "minor_account_deletion_failed",
        stage: failure,
      }));
    } else {
      deleted += 1;
    }
  }
  return { deleted, failed };
}

function openAIRequest(
  path: string,
  apiKey: string,
  body: Record<string, unknown>,
): Promise<OpenAIAnswer> {
  return postOpenAI(path, apiKey, body, { timeoutMs: 45_000 });
}

function bookedUsage(answers: OpenAIResponsePayload[]) {
  return answers.reduce(
    (usage, answer) => addUsage(usage, usageFromResponse(answer)),
    emptyUsage(),
  );
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  const suppliedSecret = request.headers.get("X-Nina-Maintenance-Secret") ?? "";
  const supabaseURL = Deno.env.get("SUPABASE_URL") ?? "";
  const secretKey = parseConfiguredKey(
    "SUPABASE_SECRET_KEYS",
    "SUPABASE_SERVICE_ROLE_KEY",
  );
  const openAIKey = Deno.env.get("OPENAI_API_KEY") ?? "";
  const safetySalt = Deno.env.get("NINA_SAFETY_ID_SALT");
  if (!supabaseURL || !secretKey) {
    return jsonResponse({ error: "service_not_configured" }, 503);
  }

  const admin = createClient(supabaseURL, secretKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: secretIsValid, error: secretError } = await admin.rpc(
    "verify_nina_maintenance_secret",
    { candidate_secret: suppliedSecret },
  );
  if (secretError || secretIsValid !== true) {
    return jsonResponse({ error: "not_authenticated" }, 401);
  }

  const { data: retention, error: retentionError } = await admin.rpc(
    "run_nina_retention",
  );
  if (retentionError) {
    console.error(JSON.stringify({
      event: "nina_retention_failed",
      code: retentionError.code,
    }));
  }

  const {
    data: waitlistRetention,
    error: waitlistRetentionError,
  } = await admin.rpc("run_waitlist_retention");
  if (waitlistRetentionError) {
    console.error(JSON.stringify({
      event: "waitlist_retention_failed",
      code: waitlistRetentionError.code,
    }));
  }

  const minorAccounts = await deleteMinorAccountsWithoutAHouse(admin);

  const insightsSkipped = (code: string) => {
    console.warn(JSON.stringify({
      event: "nina_insights_skipped",
      code,
    }));
    return jsonResponse({
      retention,
      waitlist_retention: waitlistRetention,
      minor_accounts: minorAccounts,
      candidates: 0,
      completed: 0,
      failed: 0,
      insights: "skipped_not_configured",
    }, retentionError || waitlistRetentionError ? 503 : 200);
  };

  if (!openAIKey) return insightsSkipped("openai_not_configured");
  // No insight reaches OpenAI without the safety identifier every chat turn
  // carries, so a missing salt skips them all.
  if (!isSafetySalt(safetySalt)) {
    return insightsSkipped("safety_salt_not_configured");
  }

  const { data, error } = await admin.rpc("get_nina_weekly_candidates");
  if (error) {
    return jsonResponse({ error: "candidate_query_failed" }, 503);
  }

  const candidates = Array.isArray(data) ? data as WeeklyCandidate[] : [];
  let completedCount = 0;
  let failedCount = 0;

  for (const candidate of candidates.slice(0, 25)) {
    const startedAt = performance.now();
    const { data: rosterData, error: rosterError } = await admin.rpc(
      "get_nina_model_roster",
      { target_family_id: candidate.family_id, requesting_user_id: null },
    );
    const roster: unknown[] = Array.isArray(rosterData) ? rosterData : [];
    if (rosterError || !Array.isArray(rosterData) || !roster.every(isRosterEntry)) {
      failedCount += 1;
      continue;
    }
    // Only consenting carriers are named in the insight; anyone else whose
    // name surfaces in the metrics reaches the model as a code.
    const names = new Pseudonymizer(roster.filter(isRosterEntry), null);
    const input = [{
      role: "user",
      content: [{
        type: "input_text",
        text: JSON.stringify(names.deep({
          ...candidate,
          open_tasks_by_owner: names.structuredKeys(
            candidate.open_tasks_by_owner ?? {},
          ),
        })),
      }],
    }];
    const tokenRequest = {
      model: insightModel,
      instructions: insightInstructions,
      input,
      text: {
        verbosity: "low",
        format: {
          type: "json_schema",
          name: "nina_weekly_insights",
          strict: true,
          schema: insightResponseSchema,
        },
      },
    };

    let inputTokens = 0;
    try {
      const count = await openAIRequest(
        "/v1/responses/input_tokens",
        openAIKey,
        tokenRequest,
      );
      const countValue =
        (count.payload as unknown as { input_tokens?: number }).input_tokens;
      if (!count.ok || typeof countValue !== "number") {
        throw new NinaFailure("token_count_unavailable");
      }
      inputTokens = countValue;
      if (inputTokens > maxInputTokens) {
        throw new NinaFailure("input_too_large");
      }
    } catch {
      failedCount += 1;
      continue;
    }

    const pricingEnv = environmentPricing();
    const reservation = estimateInsightReservationMicrousd(
      inputTokens,
      pricingEnv,
    );
    const { data: runID, error: reserveError } = await admin.rpc(
      "reserve_nina_insight_run",
      {
        target_family_id: candidate.family_id,
        requested_model: insightModel,
        reserved_cost_microusd: reservation,
        pricing_version: pricingVersion,
      },
    );
    if (reserveError || typeof runID !== "string") {
      failedCount += 1;
      continue;
    }

    let usedModel = insightModel;
    let aggregateUsage = emptyUsage();
    let actualCost = 0;
    try {
      const householdSafetyIdentifier = await safetyIdentifier(
        safetySalt,
        candidate.family_id,
      );
      let generated = await openAIRequest("/v1/responses", openAIKey, {
        ...tokenRequest,
        store: false,
        reasoning: { effort: "low" },
        max_output_tokens: maxInsightOutputTokens,
        prompt_cache_options: { mode: "explicit" },
        safety_identifier: householdSafetyIdentifier,
      });

      const primaryUsage = bookedUsage(generated.answers);
      aggregateUsage = addUsage(aggregateUsage, primaryUsage);
      actualCost += calculateActualCostMicrousd(
        primaryUsage,
        pricingForModel(insightModel, pricingEnv),
      );

      if (
        !generated.ok
        && shouldUseInsightFallback(generated.status, generated.payload)
      ) {
        usedModel = insightFallbackModel;
        generated = await openAIRequest("/v1/responses", openAIKey, {
          ...tokenRequest,
          model: usedModel,
          store: false,
          reasoning: { effort: "low" },
          max_output_tokens: maxInsightOutputTokens,
          prompt_cache_key: "nina-weekly-insights-v2",
          safety_identifier: householdSafetyIdentifier,
        });
        const fallbackUsage = bookedUsage(generated.answers);
        aggregateUsage = addUsage(aggregateUsage, fallbackUsage);
        actualCost += calculateActualCostMicrousd(
          fallbackUsage,
          pricingForModel(usedModel, pricingEnv),
        );
      }

      if (!generated.ok) {
        throw upstreamFailure(generated.status);
      }

      const outputText = extractOutputText(generated.payload);
      if (!outputText) throw new NinaFailure("invalid_assistant_response");
      let structured: { insights?: unknown[] };
      try {
        structured = JSON.parse(outputText) as { insights?: unknown[] };
      } catch {
        throw new NinaFailure("invalid_assistant_response");
      }
      if (!Array.isArray(structured.insights) || structured.insights.length === 0) {
        throw new NinaFailure("invalid_assistant_response");
      }

      // The insight's own words are moderated before any real name is put
      // back, and a flagged insight is never stored for the house to read.
      const verdict = await moderate(
        openAIKey,
        moderationTexts(insightTexts(structured.insights)),
      );
      if (verdict.flagged) throw new NinaFailure("insight_moderated");

      const latency = Math.round(performance.now() - startedAt);
      await admin
        .from("nina_ai_runs")
        .update({ model: usedModel })
        .eq("id", runID);
      const { error: completeError } = await admin.rpc(
        "complete_nina_insight_run",
        {
          target_run_id: runID,
          insight_rows: names.restoreDeep(structured.insights),
          usage_input_tokens: aggregateUsage.inputTokens,
          usage_cached_input_tokens: aggregateUsage.cachedInputTokens,
          usage_output_tokens: aggregateUsage.outputTokens,
          usage_reasoning_tokens: aggregateUsage.reasoningTokens,
          actual_cost_microusd: actualCost,
          request_latency_ms: latency,
        },
      );
      if (completeError) throw new NinaFailure("persistence_failed");

      completedCount += 1;
      console.info(JSON.stringify({
        event: "nina_insight_completed",
        run_id: runID,
        family_id: candidate.family_id,
        model: usedModel,
        latency_ms: latency,
        actual_microusd: actualCost,
      }));
    } catch (caught) {
      failedCount += 1;
      const code = failureCode(caught);
      await admin.rpc("record_failed_nina_ai_run", {
        target_run_id: runID,
        failure_code: code,
        usage_input_tokens: aggregateUsage.inputTokens,
        usage_cached_input_tokens: aggregateUsage.cachedInputTokens,
        usage_output_tokens: aggregateUsage.outputTokens,
        usage_reasoning_tokens: aggregateUsage.reasoningTokens,
        actual_cost_microusd: actualCost,
        request_latency_ms: Math.round(performance.now() - startedAt),
      });
      console.error(JSON.stringify({
        event: "nina_insight_failed",
        run_id: runID,
        family_id: candidate.family_id,
        code,
        upstream_status: upstreamStatus(caught),
      }));
    }
  }

  return jsonResponse({
    retention,
    waitlist_retention: waitlistRetention,
    minor_accounts: minorAccounts,
    candidates: candidates.length,
    completed: completedCount,
    failed: failedCount,
  }, retentionError || waitlistRetentionError ? 503 : 200);
});
