import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2";
import {
  addUsage,
  calculateActualCostMicrousd,
  emptyUsage,
  environmentPricing,
  estimateInteractiveReservationMicrousd,
  extractOutputText,
  functionCalls,
  interactiveModel,
  isSafetySalt,
  isStructuredOutput,
  isToolCallBatchAllowed,
  legacySuggestionFromProposals,
  maxInputTokens,
  maxInteractiveOutputTokens,
  maxToolCalls,
  maxToolRounds,
  type ModerationVerdict,
  moderationVerdict,
  OpenAIResponsePayload,
  pricingForModel,
  pricingVersion,
  proposalResponseSchema,
  safeErrorCode,
  safetyIdentifier,
  usageFromResponse,
} from "../_shared/nina-ai.ts";
import {
  attachmentMetadata,
  NinaChatAttachment,
  NinaChatRequest,
  readNinaChatRequest,
} from "../_shared/nina-chat-request.ts";
import {
  asksForMedicalGuidance,
  ninaInputRefusal,
  ninaMedicalRefusal,
  ninaOutputRefusal,
  ninaSupportReply,
  ninaSystemPrompt,
} from "../_shared/nina-chat-policy.ts";
import { fillMissingDueAt, ninaLocalNow } from "../_shared/nina-due-date.ts";
import { houseWorkloadKey, summarizeWorkload } from "../_shared/nina-workload.ts";
import { minimizeMembersForModel } from "../_shared/nina-member-context.ts";
import { isRosterEntry, Pseudonymizer } from "../_shared/nina-pseudonyms.ts";
import {
  matchesSearch,
  normalizedSearch,
  searchCandidateLimit,
} from "../_shared/nina-search.ts";

type NinaChatStart = {
  idempotent: boolean;
  run_id: string;
  thread_id: string;
  status: string;
};

type NinaState = {
  messages?: Array<Record<string, unknown>>;
  memories?: Array<Record<string, unknown>>;
};

const readOnlyTools = [
  {
    type: "function",
    name: "search_tasks",
    description:
      "Search household tasks, schedules, reminders, appointments, and recurring obligations. Read-only.",
    strict: true,
    parameters: {
      type: "object",
      properties: {
        query: { type: "string" },
        include_completed: { type: "boolean" },
      },
      required: ["query", "include_completed"],
      additionalProperties: false,
    },
  },
  {
    type: "function",
    name: "search_shopping",
    description:
      "Search household shopping items. Read-only. Use for groceries, supplies, and purchase status.",
    strict: true,
    parameters: {
      type: "object",
      properties: {
        query: { type: "string" },
        include_checked: { type: "boolean" },
      },
      required: ["query", "include_checked"],
      additionalProperties: false,
    },
  },
  {
    type: "function",
    name: "search_memories",
    description:
      "Search confirmed memories visible to the current adult. Read-only. Never exposes another person's private memories.",
    strict: true,
    parameters: {
      type: "object",
      properties: {
        query: { type: "string" },
      },
      required: ["query"],
      additionalProperties: false,
    },
  },
  {
    type: "function",
    name: "get_workload_summary",
    description:
      "Return deterministic task counts per household member. Read-only. Use for workload and redistribution questions. The key Casa is work the house carries and is never a person.",
    strict: true,
    parameters: {
      type: "object",
      properties: {},
      required: [],
      additionalProperties: false,
    },
  },
] as const;

function jsonResponse(body: unknown, status = 200): Response {
  return Response.json(body, {
    status,
    headers: {
      "Cache-Control": "no-store",
    },
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

function buildUserContent(
  context: Record<string, unknown>,
  attachments: NinaChatAttachment[],
): Array<Record<string, unknown>> {
  const content: Array<Record<string, unknown>> = [{
    type: "input_text",
    text: JSON.stringify(context),
  }];

  for (const attachment of attachments) {
    const dataURL =
      `data:${attachment.mime_type};base64,${attachment.data_base64}`;

    if (attachment.kind === "image") {
      content.push({
        type: "input_image",
        image_url: dataURL,
        detail: "auto",
      });
    } else {
      content.push({
        type: "input_file",
        filename: attachment.filename,
        file_data: dataURL,
      });
    }
  }

  return content;
}

async function openAIJSON(
  path: string,
  apiKey: string,
  body: Record<string, unknown>,
  timeoutMs = 35_000,
): Promise<{ response: Response; payload: OpenAIResponsePayload }> {
  const response = await fetch(`https://api.openai.com${path}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(timeoutMs),
  });
  const payload = await response.json() as OpenAIResponsePayload;
  return { response, payload };
}

async function moderate(
  apiKey: string,
  inputs: Array<Record<string, unknown>>,
): Promise<ModerationVerdict> {
  if (inputs.length === 0) {
    return { flagged: false, sexualMinors: false, selfHarm: false };
  }

  const response = await fetch("https://api.openai.com/v1/moderations", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "omni-moderation-latest",
      input: inputs,
    }),
    signal: AbortSignal.timeout(15_000),
  });

  if (!response.ok) {
    throw new Error("moderation_unavailable");
  }

  return moderationVerdict(await response.json());
}

// The moderation input is the pseudonymized text, so no name the model may
// not see reaches the moderation endpoint either.
async function moderateInput(
  apiKey: string,
  pseudonymizedMessage: string,
  body: NinaChatRequest,
): Promise<ModerationVerdict> {
  const inputs: Array<Record<string, unknown>> = [];

  if (pseudonymizedMessage.trim().length > 0) {
    inputs.push({ type: "text", text: pseudonymizedMessage.trim() });
  }

  for (const attachment of body.attachments ?? []) {
    if (attachment.kind !== "image") continue;
    inputs.push({
      type: "image_url",
      image_url: {
        url: `data:${attachment.mime_type};base64,${attachment.data_base64}`,
      },
    });
  }

  return await moderate(apiKey, inputs);
}

async function moderateOutput(
  apiKey: string,
  modelOutput: { reply: string; proposals: unknown[] },
): Promise<ModerationVerdict> {
  const texts = [modelOutput.reply];
  for (const proposal of modelOutput.proposals) {
    const entry = proposal as {
      title?: unknown;
      detail?: unknown;
      payload?: { title?: unknown; detail?: unknown };
    };
    for (
      const value of [
        entry.title,
        entry.detail,
        entry.payload?.title,
        entry.payload?.detail,
      ]
    ) {
      if (typeof value === "string" && value.trim()) texts.push(value);
    }
  }
  return await moderate(
    apiKey,
    texts.filter((text) => text.trim()).map((text) => ({ type: "text", text })),
  );
}

function minorOwnerFilter(names: Pseudonymizer): string | null {
  const excluded = [...names.excludedOwnerIDs].filter((id) =>
    /^[0-9a-f-]{36}$/i.test(id)
  );
  return excluded.length === 0
    ? null
    : `owner_member_id.is.null,owner_member_id.not.in.(${excluded.join(",")})`;
}

// A task owned by a child, a teen or a person of unknown age never reaches
// the model through any tool, and neither does that person as a bucket.
async function runReadOnlyTool(
  client: SupabaseClient,
  familyID: string,
  userID: string,
  name: string,
  rawArguments: string,
  names: Pseudonymizer,
): Promise<Record<string, unknown>> {
  let args: Record<string, unknown> = {};
  try {
    args = JSON.parse(rawArguments) as Record<string, unknown>;
  } catch {
    return { error: "invalid_arguments" };
  }

  const query = normalizedSearch(args.query);

  switch (name) {
    case "search_tasks": {
      let request = client
        .from("tasks")
        .select(
          "id,title,subtitle,owner_member_id,owner_label,due_label,due_at,category_id,priority,recurrence_rule,snoozed_until,is_done",
        )
        .eq("family_id", familyID)
        .order("due_at", { ascending: true, nullsFirst: false })
        .limit(searchCandidateLimit);
      const ownerFilter = minorOwnerFilter(names);
      if (ownerFilter) request = request.or(ownerFilter);
      if (args.include_completed !== true) request = request.eq("is_done", false);
      const { data, error } = await request;
      const tasks = names.withoutMinorWork(data ?? [])
        .filter((row) => matchesSearch(row, query, ["title", "subtitle"]))
        .slice(0, 12)
        .map(({ owner_member_id: owner, ...task }) => ({
          ...task,
          owner_label: owner
            ? names.structuredName(String(owner), String(task.owner_label ?? ""))
            : task.owner_label,
        }));
      return error ? { error: "tool_unavailable" } : { tasks };
    }
    case "search_shopping": {
      let request = client
        .from("shopping_items")
        .select("id,title,amount,owner_member_id,owner_label,is_checked")
        .eq("family_id", familyID)
        .order("created_at", { ascending: false })
        .limit(searchCandidateLimit);
      const ownerFilter = minorOwnerFilter(names);
      if (ownerFilter) request = request.or(ownerFilter);
      if (args.include_checked !== true) request = request.eq("is_checked", false);
      const { data, error } = await request;
      const items = names.withoutMinorWork(data ?? [])
        .filter((row) => matchesSearch(row, query, ["title"]))
        .slice(0, 12)
        .map(({ owner_member_id: owner, ...item }) => ({
          ...item,
          owner_label: owner
            ? names.structuredName(String(owner), String(item.owner_label ?? ""))
            : item.owner_label,
        }));
      return error ? { error: "tool_unavailable" } : { items };
    }
    case "search_memories": {
      const { data, error } = await client
        .from("memory_items")
        .select("id,title,body,visibility,confidence")
        .eq("family_id", familyID)
        .eq("status", "confirmed")
        .or(`owner_user_id.eq.${userID},visibility.eq.shared`)
        .order("updated_at", { ascending: false })
        .limit(searchCandidateLimit);
      const memories = (data ?? [])
        .filter((row) => matchesSearch(row, query, ["title", "body"]))
        .slice(0, 12);
      return error ? { error: "tool_unavailable" } : { memories };
    }
    case "get_workload_summary": {
      const [taskResult, memberResult] = await Promise.all([
        client
          .from("tasks")
          .select("owner_member_id,owner_label,is_done,priority,task_kind")
          .eq("family_id", familyID),
        client
          .from("family_members")
          .select("id,name,relationship,household_role")
          .eq("family_id", familyID)
          .order("created_at")
          .order("id"),
      ]);
      if (taskResult.error || memberResult.error) {
        return { error: "tool_unavailable" };
      }

      // A bucket is named from its member id, never from the name as text,
      // so an adult who shares a minor's first name keeps their own count.
      return {
        house_owner_label: houseWorkloadKey,
        workload: summarizeWorkload(
          names.withoutMinorWork(taskResult.data ?? []),
          (memberResult.data ?? [])
            .filter((member) => !names.excludedOwnerIDs.has(String(member.id)))
            .map((member) => ({
              ...member,
              name: names.structuredName(String(member.id), String(member.name ?? "")),
            })),
        ),
      };
    }
    default:
      return { error: "unknown_tool" };
  }
}

function attachLegacySuggestion(result: Record<string, unknown>) {
  const proposals = Array.isArray(result.proposals)
    ? result.proposals as Parameters<typeof legacySuggestionFromProposals>[0]
    : [];
  return {
    ...result,
    suggestion: legacySuggestionFromProposals(proposals),
  };
}

function normalizedText(value: string): string {
  return value
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .toLocaleLowerCase("pt-BR");
}

function deterministicSensitiveReply(message: string): string | null {
  const text = normalizedText(message);
  if (asksForMedicalGuidance(message)) {
    return ninaMedicalRefusal;
  }

  const asksLegalConclusion =
    /(contrato|processo|juridic|legal|lei)/.test(text)
    && /(e legal|assine|assinar|validade|valido|decida por mim)/.test(text);
  if (asksLegalConclusion) {
    return "Não posso concluir validade jurídica nem assinar por você. Posso ajudar a listar pontos para revisar, mas a decisão deve passar por um profissional qualificado.";
  }

  const asksInvestmentDecision =
    /(invista|investir|acao|acoes|cripto|bitcoin|dinheiro)/.test(text)
    && /(todo|melhor|compre agora|venda agora|garantid)/.test(text);
  if (asksInvestmentDecision) {
    return "Não posso decidir investimento nem movimentar dinheiro da casa. Posso ajudar a organizar critérios e perguntas para avaliar com um profissional financeiro.";
  }

  return null;
}

function deterministicWorkloadOutput(message: string) {
  const text = normalizedText(message);
  const asksRedistribution =
    /tarefas/.test(text)
    && /(redistribu|equilibr|divid|sobrecarreg|muito mais)/.test(text)
    && /(sugira|proponha|propor|revisar|nao mude|nao altere)/.test(text);

  if (!asksRedistribution) return null;

  return {
    reply:
      "Posso sugerir uma revisão da divisão sem mudar nada automaticamente. Confirme se quer criar uma tarefa para redistribuir as pendências abertas.",
    proposals: [{
      id: crypto.randomUUID(),
      kind: "task",
      title: "Revisar divisão das tarefas abertas",
      detail:
        "Comparar as tarefas abertas por responsável e combinar uma redistribuição mais equilibrada.",
      action_title: "Criar tarefa de revisão",
      payload: {
        title: "Revisar divisão das tarefas abertas",
        detail:
          "Comparar as tarefas abertas por responsável e combinar uma redistribuição mais equilibrada.",
        owner: "Casa",
        due_label: "Sem data",
        due_at: null,
        category: "home",
        symbol_name: "person.2.fill",
        amount: "",
        visibility: null,
        confidence: 0.72,
        deduplication_key: "workload-redistribution-review",
      },
    }],
  };
}

async function recordFailedRun(
  adminClient: SupabaseClient,
  runID: string,
  code: string,
  usage: ReturnType<typeof emptyUsage>,
  actualCost: number,
  latency: number,
) {
  await adminClient.rpc("record_failed_nina_ai_run", {
    target_run_id: runID,
    failure_code: code,
    usage_input_tokens: usage.inputTokens,
    usage_cached_input_tokens: usage.cachedInputTokens,
    usage_output_tokens: usage.outputTokens,
    usage_reasoning_tokens: usage.reasoningTokens,
    actual_cost_microusd: actualCost,
    request_latency_ms: latency,
  });
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  const startedAt = performance.now();
  const authorization = request.headers.get("Authorization");
  const supabaseURL = Deno.env.get("SUPABASE_URL") ?? "";
  const publishableKey = parseConfiguredKey(
    "SUPABASE_PUBLISHABLE_KEYS",
    "SUPABASE_ANON_KEY",
  );
  const secretKey = parseConfiguredKey(
    "SUPABASE_SECRET_KEYS",
    "SUPABASE_SERVICE_ROLE_KEY",
  );
  const openAIKey = Deno.env.get("OPENAI_API_KEY") ?? "";
  const safetySalt = Deno.env.get("NINA_SAFETY_ID_SALT");

  if (
    !authorization?.startsWith("Bearer ")
    || !supabaseURL
    || !publishableKey
  ) {
    return jsonResponse({ error: "not_authenticated" }, 401);
  }

  if (!secretKey || !openAIKey || !isSafetySalt(safetySalt)) {
    return jsonResponse({ error: "service_not_configured" }, 503);
  }

  const read = await readNinaChatRequest(request);
  if (!read.ok) {
    return jsonResponse({ error: read.error }, read.status);
  }
  const body = read.request;

  const clientMessageID = body.message_id ?? crypto.randomUUID();
  const token = authorization.slice("Bearer ".length);
  const userClient = createClient(supabaseURL, publishableKey, {
    global: { headers: { Authorization: authorization } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const adminClient = createClient(supabaseURL, secretKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const {
    data: { user },
    error: userError,
  } = await userClient.auth.getUser(token);

  if (userError || !user) {
    return jsonResponse({ error: "not_authenticated" }, 401);
  }

  const { data: membership, error: membershipError } = await userClient
    .from("family_members")
    .select("id,household_role")
    .eq("family_id", body.family_id)
    .eq("user_id", user.id)
    .maybeSingle();

  if (membershipError) {
    return jsonResponse({ error: "context_unavailable" }, 503);
  }
  if (membership?.household_role !== "adult") {
    return jsonResponse({ error: "adult_access_required" }, 403);
  }

  const model = interactiveModel;
  const pricing = pricingForModel(model, environmentPricing());
  const reservedCost = estimateInteractiveReservationMicrousd(pricing);

  const { data: startData, error: startError } = await userClient.rpc(
    "begin_nina_chat_run",
    {
      target_family_id: body.family_id,
      client_message_id: clientMessageID,
      message_text: body.message,
      attachment_metadata: attachmentMetadata(body.attachments ?? []),
      requested_model: model,
      reserved_cost_microusd: reservedCost,
      pricing_version: pricingVersion,
    },
  );

  if (startError) {
    // Stable codes are matched whole: nina_ai_consent_required contains
    // ai_consent_required, and a substring match would confuse the two.
    const code = (startError.message ?? "").trim();
    if (code === "nina_rate_limited") {
      return jsonResponse({ error: "rate_limited" }, 429);
    }
    if (code === "nina_budget_exceeded") {
      return jsonResponse({ error: "monthly_budget_reached" }, 429);
    }
    if (code === "nina_adult_access_required") {
      return jsonResponse({ error: "adult_access_required" }, 403);
    }
    if (code === "age_confirmation_required") {
      return jsonResponse({ error: "nina_age_confirmation_required" }, 403);
    }
    if (code === "nina_ai_blocked") {
      return jsonResponse({ error: "nina_ai_blocked" }, 403);
    }
    if (code === "nina_ai_consent_required") {
      return jsonResponse({ error: "ai_consent_required" }, 403);
    }
    if (code === "nina_consent_outdated") {
      return jsonResponse({ error: "nina_consent_outdated" }, 403);
    }
    if (code === "nina_transfer_consent_required") {
      return jsonResponse({ error: "nina_transfer_consent_required" }, 403);
    }
    if (code === "nina_attachments_require_premium") {
      return jsonResponse({ error: "attachments_require_premium" }, 403);
    }
    console.error(JSON.stringify({
      event: "nina_run_start_failed",
      code: startError.code,
    }));
    return jsonResponse({ error: "service_unavailable" }, 503);
  }

  const run = startData as NinaChatStart;
  if (run.idempotent) {
    if (run.status === "completed") {
      const { data, error } = await userClient.rpc("get_nina_chat_result", {
        target_run_id: run.run_id,
      });
      if (!error && data) {
        return jsonResponse(attachLegacySuggestion(data as Record<string, unknown>));
      }
    }
    return jsonResponse({ error: "request_in_progress" }, 409);
  }

  console.info(JSON.stringify({
    event: "nina_run_started",
    run_id: run.run_id,
    model,
    reserved_microusd: reservedCost,
  }));

  const emptyFailureUsage = emptyUsage();

  const [familyResult, profileResult, membersResult, stateResult, rosterResult] =
    await Promise.all([
      userClient
        .from("families")
        .select("id,name")
        .eq("id", body.family_id)
        .single(),
      userClient
        .from("profiles")
        .select("display_name,communication_preference,memory_note,availability_note")
        .eq("id", user.id)
        .maybeSingle(),
      userClient
        .from("family_members")
        .select("id,name,relationship,household_role,memory_note,pet_species,pet_breed")
        .eq("family_id", body.family_id)
        .limit(12),
      userClient.rpc("get_current_nina_state", {
        target_family_id: body.family_id,
      }),
      adminClient.rpc("get_nina_model_roster", {
        target_family_id: body.family_id,
        requesting_user_id: user.id,
      }),
    ]);

  const rosterRows: unknown[] = Array.isArray(rosterResult.data)
    ? rosterResult.data
    : [];
  if (
    familyResult.error
    || profileResult.error
    || membersResult.error
    || stateResult.error
    || rosterResult.error
    || !Array.isArray(rosterResult.data)
    || !rosterRows.every(isRosterEntry)
  ) {
    await recordFailedRun(
      adminClient,
      run.run_id,
      "context_unavailable",
      emptyFailureUsage,
      0,
      Math.round(performance.now() - startedAt),
    );
    return jsonResponse({ error: "context_unavailable" }, 503);
  }

  const names = new Pseudonymizer(
    rosterRows.filter(isRosterEntry),
    (familyResult.data as { name?: string } | null)?.name ?? null,
  );
  const modelMessage = names.text(body.message.trim());

  let needsSupport = false;
  try {
    const verdict = await moderateInput(openAIKey, modelMessage, body);
    if (verdict.sexualMinors) {
      const { error: holdError } = await adminClient.rpc(
        "hold_nina_chat_run_for_child_safety",
        { target_run_id: run.run_id },
      );
      console.error(JSON.stringify({
        event: holdError ? "child_safety_hold_failed" : "child_safety_hold_created",
        run_id: run.run_id,
      }));
    } else if (verdict.flagged && !verdict.selfHarm) {
      // A refused message never stays on the server in its original words,
      // so a later refresh cannot bring it back to the phone either.
      const { error: redactError } = await adminClient.rpc(
        "redact_refused_nina_message",
        { target_run_id: run.run_id },
      );
      if (redactError) {
        console.error(JSON.stringify({
          event: "refused_message_redaction_failed",
          run_id: run.run_id,
        }));
      }
    }
    if (verdict.selfHarm) {
      needsSupport = true;
    } else if (verdict.flagged) {
      await recordFailedRun(
        adminClient,
        run.run_id,
        "input_not_supported",
        emptyFailureUsage,
        0,
        Math.round(performance.now() - startedAt),
      );
      return jsonResponse({
        error: "input_not_supported",
        reply: ninaInputRefusal,
      }, 400);
    }
  } catch {
    await recordFailedRun(
      adminClient,
      run.run_id,
      "safety_check_unavailable",
      emptyFailureUsage,
      0,
      Math.round(performance.now() - startedAt),
    );
    return jsonResponse({ error: "safety_check_unavailable" }, 503);
  }

  const deterministicReply = needsSupport
    ? ninaSupportReply
    : deterministicSensitiveReply(body.message);
  if (deterministicReply) {
    const assistantMessageID = crypto.randomUUID();
    const latency = Math.round(performance.now() - startedAt);
    const { data: completed, error: completeError } = await adminClient.rpc(
      "complete_nina_chat_run",
      {
        target_run_id: run.run_id,
        assistant_message_id: assistantMessageID,
        assistant_reply: deterministicReply,
        proposals: [],
        usage_input_tokens: 0,
        usage_cached_input_tokens: 0,
        usage_output_tokens: 0,
        usage_reasoning_tokens: 0,
        actual_cost_microusd: 0,
        request_latency_ms: latency,
      },
    );

    if (completeError || !completed) {
      await recordFailedRun(
        adminClient,
        run.run_id,
        "persistence_failed",
        emptyFailureUsage,
        0,
        latency,
      );
      return jsonResponse({ error: "service_unavailable" }, 503);
    }

    console.info(JSON.stringify({
      event: "nina_run_completed",
      run_id: run.run_id,
      model: needsSupport ? "deterministic_support" : "deterministic_safety",
      latency_ms: latency,
      actual_microusd: 0,
      tool_calls: 0,
    }));

    return jsonResponse(
      attachLegacySuggestion(completed as Record<string, unknown>),
    );
  }

  const workloadOutput = deterministicWorkloadOutput(body.message);
  if (workloadOutput) {
    const assistantMessageID = crypto.randomUUID();
    const latency = Math.round(performance.now() - startedAt);
    const { data: completed, error: completeError } = await adminClient.rpc(
      "complete_nina_chat_run",
      {
        target_run_id: run.run_id,
        assistant_message_id: assistantMessageID,
        assistant_reply: workloadOutput.reply,
        proposals: workloadOutput.proposals,
        usage_input_tokens: 0,
        usage_cached_input_tokens: 0,
        usage_output_tokens: 0,
        usage_reasoning_tokens: 0,
        actual_cost_microusd: 0,
        request_latency_ms: latency,
      },
    );

    if (completeError || !completed) {
      await recordFailedRun(
        adminClient,
        run.run_id,
        "persistence_failed",
        emptyFailureUsage,
        0,
        latency,
      );
      return jsonResponse({ error: "service_unavailable" }, 503);
    }

    console.info(JSON.stringify({
      event: "nina_run_completed",
      run_id: run.run_id,
      model: "deterministic_workload",
      latency_ms: latency,
      actual_microusd: 0,
      tool_calls: 0,
    }));

    return jsonResponse(
      attachLegacySuggestion(completed as Record<string, unknown>),
    );
  }

  const state = (stateResult.data ?? {}) as NinaState;
  const recentMessages = (state.messages ?? []).slice(-12).map((message) => ({
    sender: message.sender,
    text: message.text,
    created_at: message.created_at,
    attachments: message.attachments,
  }));
  const finalMessage = recentMessages.at(-1);
  if (
    finalMessage?.sender === "user"
    && typeof finalMessage.text === "string"
    && finalMessage.text.trim() === body.message.trim()
  ) {
    recentMessages.pop();
  }

  const turnClock = new Date();
  const householdContext = names.deep({
    local_now: ninaLocalNow(turnClock),
    family: familyResult.data,
    current_user: profileResult.data
      ? {
        ...profileResult.data,
        display_name: names.structuredName(
          String(membership.id),
          String(profileResult.data.display_name ?? ""),
        ),
      }
      : null,
    members: names.memberContext(
      minimizeMembersForModel(membersResult.data ?? []),
    ),
    confirmed_visible_memories: state.memories ?? [],
    recent_private_messages: recentMessages,
    new_message: modelMessage,
    new_attachments: attachmentMetadata(body.attachments ?? []),
  });

  const userContent = buildUserContent(
    householdContext,
    body.attachments ?? [],
  );
  const initialInput: Array<Record<string, unknown>> = [{
    role: "user",
    content: userContent,
  }];
  const baseRequest = {
    model,
    instructions: ninaSystemPrompt,
    input: initialInput,
    tools: readOnlyTools,
    tool_choice: "auto",
    text: {
      verbosity: "low",
      format: {
        type: "json_schema",
        name: "nina_chat_v2",
        strict: true,
        schema: proposalResponseSchema,
      },
    },
  };
  const requesterSafetyIdentifier = await safetyIdentifier(safetySalt, user.id);

  let inputTokenCount: number;
  try {
    const { response, payload } = await openAIJSON(
      "/v1/responses/input_tokens",
      openAIKey,
      baseRequest,
      20_000,
    );
    if (!response.ok || typeof (payload as { input_tokens?: unknown }).input_tokens !== "number") {
      await recordFailedRun(
        adminClient,
        run.run_id,
        "token_count_unavailable",
        emptyFailureUsage,
        0,
        Math.round(performance.now() - startedAt),
      );
      return jsonResponse({ error: "token_count_unavailable" }, 503);
    }
    inputTokenCount = (payload as unknown as { input_tokens: number }).input_tokens;
  } catch {
    await recordFailedRun(
      adminClient,
      run.run_id,
      "token_count_unavailable",
      emptyFailureUsage,
      0,
      Math.round(performance.now() - startedAt),
    );
    return jsonResponse({ error: "token_count_unavailable" }, 503);
  }

  if (inputTokenCount > maxInputTokens) {
    await recordFailedRun(
      adminClient,
      run.run_id,
      "input_too_large",
      emptyFailureUsage,
      0,
      Math.round(performance.now() - startedAt),
    );
    return jsonResponse({ error: "input_too_large" }, 413);
  }

  console.info(JSON.stringify({
    event: "nina_input_counted",
    run_id: run.run_id,
    input_tokens: inputTokenCount,
  }));

  let finalPayload: OpenAIResponsePayload | null = null;
  let conversationInput = initialInput;
  let totalToolCalls = 0;
  let aggregateUsage = emptyUsage();
  let actualCost = 0;

  try {
    for (let round = 0; round <= maxToolRounds; round += 1) {
      if (round > 0) {
        const { response: countResponse, payload: countPayload } =
          await openAIJSON(
            "/v1/responses/input_tokens",
            openAIKey,
            {
              ...baseRequest,
              input: conversationInput,
            },
            20_000,
          );
        const roundInputTokens =
          (countPayload as unknown as { input_tokens?: number }).input_tokens;
        if (!countResponse.ok || typeof roundInputTokens !== "number") {
          throw new Error("token_count_unavailable");
        }
        if (roundInputTokens > maxInputTokens) {
          throw new Error("input_too_large");
        }
      }

      const { response, payload } = await openAIJSON(
        "/v1/responses",
        openAIKey,
        {
          ...baseRequest,
          input: conversationInput,
          store: false,
          include: ["reasoning.encrypted_content"],
          reasoning: { effort: "medium" },
          max_output_tokens: maxInteractiveOutputTokens,
          prompt_cache_options: { mode: "explicit" },
          safety_identifier: requesterSafetyIdentifier,
        },
      );

      const responseUsage = usageFromResponse(payload);
      aggregateUsage = addUsage(aggregateUsage, responseUsage);
      actualCost += calculateActualCostMicrousd(responseUsage, pricing);

      if (!response.ok) {
        throw new Error(safeErrorCode(payload));
      }

      const calls = functionCalls(payload);
      if (calls.length === 0) {
        finalPayload = payload;
        break;
      }

      if (!isToolCallBatchAllowed(round, totalToolCalls, calls.length)) {
        throw new Error("tool_limit_exceeded");
      }

      const toolOutputs = [];
      for (const call of calls) {
        totalToolCalls += 1;
        const output = await runReadOnlyTool(
          userClient,
          body.family_id,
          user.id,
          call.name,
          call.arguments,
          names,
        );
        toolOutputs.push({
          type: "function_call_output",
          call_id: call.callId,
          output: JSON.stringify(names.deep(output)),
        });
      }

      conversationInput = [
        ...conversationInput,
        ...(payload.output ?? []),
        ...toolOutputs,
      ];
    }

    if (!finalPayload) throw new Error("missing_final_response");

    const outputText = extractOutputText(finalPayload);
    if (!outputText) throw new Error("invalid_assistant_response");

    const structured = JSON.parse(outputText) as unknown;
    if (!isStructuredOutput(structured)) {
      throw new Error("invalid_assistant_response");
    }

    const datedProposals = fillMissingDueAt(structured.proposals, body.message, turnClock);
    const restoredReply = names.restoreText(structured.reply);
    const restoredProposals = names.restoreProposals(datedProposals.proposals);

    // The model's own words are what is moderated, before any real name is
    // put back, so the moderation call never carries a name either.
    const outputVerdict = await moderateOutput(openAIKey, {
      reply: structured.reply,
      proposals: datedProposals.proposals,
    });
    const assistantReply = outputVerdict.flagged ? ninaOutputRefusal : restoredReply;
    if (outputVerdict.flagged) {
      console.error(JSON.stringify({
        event: "nina_output_moderated",
        run_id: run.run_id,
        code: "nina_output_moderated",
      }));
    }

    const latency = Math.round(performance.now() - startedAt);
    const assistantMessageID = crypto.randomUUID();
    const persistedProposals = (outputVerdict.flagged ? [] : restoredProposals).map((proposal) => ({
      ...proposal,
      id: crypto.randomUUID(),
    }));
    const { data: completed, error: completeError } = await adminClient.rpc(
      "complete_nina_chat_run",
      {
        target_run_id: run.run_id,
        assistant_message_id: assistantMessageID,
        assistant_reply: assistantReply,
        proposals: persistedProposals,
        usage_input_tokens: aggregateUsage.inputTokens,
        usage_cached_input_tokens: aggregateUsage.cachedInputTokens,
        usage_output_tokens: aggregateUsage.outputTokens,
        usage_reasoning_tokens: aggregateUsage.reasoningTokens,
        actual_cost_microusd: actualCost,
        request_latency_ms: latency,
      },
    );

    if (completeError || !completed) {
      throw new Error("persistence_failed");
    }

    console.info(JSON.stringify({
      event: "nina_run_completed",
      run_id: run.run_id,
      model: finalPayload.model ?? model,
      latency_ms: latency,
      input_tokens: aggregateUsage.inputTokens,
      cached_input_tokens: aggregateUsage.cachedInputTokens,
      cache_write_input_tokens: aggregateUsage.cacheWriteInputTokens,
      output_tokens: aggregateUsage.outputTokens,
      reasoning_tokens: aggregateUsage.reasoningTokens,
      actual_microusd: actualCost,
      tool_calls: totalToolCalls,
      due_at_filled: datedProposals.filled,
      output_moderated: outputVerdict.flagged,
    }));

    return jsonResponse(
      attachLegacySuggestion(completed as Record<string, unknown>),
    );
  } catch (error) {
    const latency = Math.round(performance.now() - startedAt);
    const code = error instanceof Error
      ? error.message.slice(0, 120)
      : "unknown_error";
    await recordFailedRun(
      adminClient,
      run.run_id,
      code,
      aggregateUsage,
      actualCost,
      latency,
    );
    console.error(JSON.stringify({
      event: "nina_run_failed",
      run_id: run.run_id,
      code,
      latency_ms: latency,
    }));
    return jsonResponse({ error: "assistant_unavailable" }, 502);
  }
});
