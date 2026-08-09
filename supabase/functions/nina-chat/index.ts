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
  isStructuredOutput,
  isToolCallBatchAllowed,
  legacySuggestionFromProposals,
  maxInputTokens,
  maxInteractiveOutputTokens,
  maxToolCalls,
  maxToolRounds,
  OpenAIResponsePayload,
  pricingForModel,
  pricingVersion,
  proposalResponseSchema,
  safeErrorCode,
  usageFromResponse,
} from "../_shared/nina-ai.ts";
import {
  attachmentMetadata,
  isNinaChatRequest,
  NinaChatAttachment,
  NinaChatRequest,
} from "../_shared/nina-chat-request.ts";
import { ninaSystemPrompt } from "../_shared/nina-chat-policy.ts";

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
      "Return deterministic task counts by owner. Read-only. Use for workload and redistribution questions.",
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

async function moderateInput(
  apiKey: string,
  body: NinaChatRequest,
): Promise<boolean> {
  const inputs: Array<Record<string, unknown>> = [];

  if (body.message.trim().length > 0) {
    inputs.push({ type: "text", text: body.message.trim() });
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

  if (inputs.length === 0) return false;

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

  const payload = await response.json() as {
    results?: Array<{ flagged?: boolean }>;
  };
  return payload.results?.some((result) => result.flagged === true) ?? false;
}

function normalizedSearch(value: unknown): string {
  return typeof value === "string" ? value.trim().slice(0, 120) : "";
}

function matchesSearch(
  row: Record<string, unknown>,
  query: string,
  keys: string[],
): boolean {
  if (!query) return true;
  const normalizedQuery = query.toLocaleLowerCase("pt-BR");
  return keys.some((key) =>
    String(row[key] ?? "").toLocaleLowerCase("pt-BR").includes(normalizedQuery)
  );
}

async function runReadOnlyTool(
  client: SupabaseClient,
  familyID: string,
  userID: string,
  name: string,
  rawArguments: string,
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
          "id,title,subtitle,owner_label,due_label,due_at,category_id,priority,recurrence_rule,snoozed_until,is_done",
        )
        .eq("family_id", familyID)
        .limit(50);
      if (args.include_completed !== true) request = request.eq("is_done", false);
      const { data, error } = await request;
      const tasks = (data ?? [])
        .filter((row) => matchesSearch(row, query, ["title", "subtitle"]))
        .slice(0, 12);
      return error ? { error: "tool_unavailable" } : { tasks };
    }
    case "search_shopping": {
      let request = client
        .from("shopping_items")
        .select("id,title,amount,owner_label,is_checked")
        .eq("family_id", familyID)
        .limit(50);
      if (args.include_checked !== true) request = request.eq("is_checked", false);
      const { data, error } = await request;
      const items = (data ?? [])
        .filter((row) => matchesSearch(row, query, ["title"]))
        .slice(0, 12);
      return error ? { error: "tool_unavailable" } : { items };
    }
    case "search_memories": {
      const { data, error } = await client
        .from("memory_items")
        .select("id,title,body,visibility,confidence")
        .eq("family_id", familyID)
        .eq("status", "confirmed")
        .or(`owner_user_id.eq.${userID},visibility.eq.shared`)
        .limit(50);
      const memories = (data ?? [])
        .filter((row) => matchesSearch(row, query, ["title", "body"]))
        .slice(0, 12);
      return error ? { error: "tool_unavailable" } : { memories };
    }
    case "get_workload_summary": {
      const { data, error } = await client
        .from("tasks")
        .select("owner_label,is_done,priority")
        .eq("family_id", familyID);
      if (error) return { error: "tool_unavailable" };

      const summary = (data ?? []).reduce<Record<string, {
        open: number;
        completed: number;
        urgent: number;
      }>>((result, task) => {
        const owner = task.owner_label || "Casa";
        result[owner] ??= { open: 0, completed: 0, urgent: 0 };
        if (task.is_done) result[owner].completed += 1;
        else result[owner].open += 1;
        if (!task.is_done && task.priority === "urgent") {
          result[owner].urgent += 1;
        }
        return result;
      }, {});
      return { workload: summary };
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
  const asksMedicationChange =
    /(dose|dosagem|medicamento|remedio|receita)/.test(text)
    && /(reduz|reduza|aument|altere|alterar|mude|mudar|metade|troque|suspenda|pare)/.test(text);
  if (asksMedicationChange) {
    return "Não posso alterar dose ou instrução clínica. Posso ajudar a organizar um lembrete com a orientação original, mas confirme qualquer mudança com um profissional de saúde.";
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

  if (
    !authorization?.startsWith("Bearer ")
    || !supabaseURL
    || !publishableKey
  ) {
    return jsonResponse({ error: "not_authenticated" }, 401);
  }

  if (!secretKey || !openAIKey) {
    return jsonResponse({ error: "service_not_configured" }, 503);
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  if (!isNinaChatRequest(body)) {
    return jsonResponse({ error: "invalid_request" }, 400);
  }

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
    .select("household_role")
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
    const message = startError.message ?? "";
    if (message.includes("rate_limited")) {
      return jsonResponse({ error: "rate_limited" }, 429);
    }
    if (message.includes("budget_exceeded")) {
      return jsonResponse({ error: "monthly_budget_reached" }, 429);
    }
    if (message.includes("adult_access")) {
      return jsonResponse({ error: "adult_access_required" }, 403);
    }
    if (message.includes("attachments_require_premium")) {
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

  const [familyResult, profileResult, membersResult, stateResult] =
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
        .select("name,relationship,household_role,memory_note")
        .eq("family_id", body.family_id)
        .limit(12),
      userClient.rpc("get_current_nina_state", {
        target_family_id: body.family_id,
      }),
    ]);

  if (
    familyResult.error
    || profileResult.error
    || membersResult.error
    || stateResult.error
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

  try {
    if (await moderateInput(openAIKey, body)) {
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
        reply:
          "Não consigo ajudar com esse conteúdo. Se houver risco imediato para alguém, procure uma pessoa de confiança ou o serviço de emergência local.",
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

  const deterministicReply = deterministicSensitiveReply(body.message);
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
      model: "deterministic_safety",
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

  const householdContext = {
    local_time: new Date().toLocaleString("pt-BR", {
      timeZone: "America/Sao_Paulo",
    }),
    family: familyResult.data,
    current_user: profileResult.data,
    members: membersResult.data ?? [],
    confirmed_visible_memories: state.memories ?? [],
    recent_private_messages: recentMessages,
    new_message: body.message.trim(),
    new_attachments: attachmentMetadata(body.attachments ?? []),
  };

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
          reasoning: { effort: "low" },
          max_output_tokens: maxInteractiveOutputTokens,
          prompt_cache_key: "nina-household-assistant-v2",
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
        );
        toolOutputs.push({
          type: "function_call_output",
          call_id: call.callId,
          output: JSON.stringify(output),
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

    const latency = Math.round(performance.now() - startedAt);
    const assistantMessageID = crypto.randomUUID();
    const persistedProposals = structured.proposals.map((proposal) => ({
      ...proposal,
      id: crypto.randomUUID(),
    }));
    const { data: completed, error: completeError } = await adminClient.rpc(
      "complete_nina_chat_run",
      {
        target_run_id: run.run_id,
        assistant_message_id: assistantMessageID,
        assistant_reply: structured.reply,
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
      output_tokens: aggregateUsage.outputTokens,
      reasoning_tokens: aggregateUsage.reasoningTokens,
      actual_microusd: actualCost,
      tool_calls: totalToolCalls,
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
