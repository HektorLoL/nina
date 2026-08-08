import { createClient } from "npm:@supabase/supabase-js@2";
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
  maxInputTokens,
  maxInsightOutputTokens,
  OpenAIResponsePayload,
  pricingForModel,
  pricingVersion,
  safeErrorCode,
  shouldUseInsightFallback,
  usageFromResponse,
} from "../_shared/nina-ai.ts";

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

async function openAIRequest(
  path: string,
  apiKey: string,
  body: Record<string, unknown>,
): Promise<{ response: Response; payload: OpenAIResponsePayload }> {
  const response = await fetch(`https://api.openai.com${path}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(45_000),
  });
  return {
    response,
    payload: await response.json() as OpenAIResponsePayload,
  };
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

  if (!openAIKey) {
    console.warn(JSON.stringify({
      event: "nina_insights_skipped",
      code: "openai_not_configured",
    }));
    return jsonResponse({
      retention,
      waitlist_retention: waitlistRetention,
      candidates: 0,
      completed: 0,
      failed: 0,
      insights: "skipped_not_configured",
    }, retentionError || waitlistRetentionError ? 503 : 200);
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
    const input = [{
      role: "user",
      content: [{
        type: "input_text",
        text: JSON.stringify(candidate),
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
      if (!count.response.ok || typeof countValue !== "number") {
        throw new Error("token_count_unavailable");
      }
      inputTokens = countValue;
      if (inputTokens > maxInputTokens) throw new Error("input_too_large");
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
      let generated = await openAIRequest("/v1/responses", openAIKey, {
        ...tokenRequest,
        store: false,
        reasoning: { effort: "low" },
        max_output_tokens: maxInsightOutputTokens,
        prompt_cache_key: "nina-weekly-insights-v2",
      });

      const primaryUsage = usageFromResponse(generated.payload);
      aggregateUsage = addUsage(aggregateUsage, primaryUsage);
      actualCost += calculateActualCostMicrousd(
        primaryUsage,
        pricingForModel(insightModel, pricingEnv),
      );

      if (
        !generated.response.ok
        && shouldUseInsightFallback(generated.response.status, generated.payload)
      ) {
        usedModel = insightFallbackModel;
        generated = await openAIRequest("/v1/responses", openAIKey, {
          ...tokenRequest,
          model: usedModel,
          store: false,
          reasoning: { effort: "low" },
          max_output_tokens: maxInsightOutputTokens,
          prompt_cache_key: "nina-weekly-insights-v2",
        });
        const fallbackUsage = usageFromResponse(generated.payload);
        aggregateUsage = addUsage(aggregateUsage, fallbackUsage);
        actualCost += calculateActualCostMicrousd(
          fallbackUsage,
          pricingForModel(usedModel, pricingEnv),
        );
      }

      if (!generated.response.ok) {
        throw new Error(safeErrorCode(generated.payload));
      }

      const outputText = extractOutputText(generated.payload);
      if (!outputText) throw new Error("invalid_assistant_response");
      const structured = JSON.parse(outputText) as {
        insights?: unknown[];
      };
      if (!Array.isArray(structured.insights) || structured.insights.length === 0) {
        throw new Error("invalid_assistant_response");
      }

      const latency = Math.round(performance.now() - startedAt);
      await admin
        .from("nina_ai_runs")
        .update({ model: usedModel })
        .eq("id", runID);
      const { error: completeError } = await admin.rpc(
        "complete_nina_insight_run",
        {
          target_run_id: runID,
          insight_rows: structured.insights,
          usage_input_tokens: aggregateUsage.inputTokens,
          usage_cached_input_tokens: aggregateUsage.cachedInputTokens,
          usage_output_tokens: aggregateUsage.outputTokens,
          usage_reasoning_tokens: aggregateUsage.reasoningTokens,
          actual_cost_microusd: actualCost,
          request_latency_ms: latency,
        },
      );
      if (completeError) throw new Error("persistence_failed");

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
      const code = caught instanceof Error
        ? caught.message.slice(0, 120)
        : "unknown_error";
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
      }));
    }
  }

  return jsonResponse({
    retention,
    waitlist_retention: waitlistRetention,
    candidates: candidates.length,
    completed: completedCount,
    failed: failedCount,
  }, retentionError || waitlistRetentionError ? 503 : 200);
});
