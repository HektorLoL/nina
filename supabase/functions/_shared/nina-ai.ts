export type NinaPurpose = "interactive" | "insights";

export type NinaUsage = {
  inputTokens: number;
  cachedInputTokens: number;
  outputTokens: number;
  reasoningTokens: number;
};

export type ModelPricing = {
  inputUsdPerMillion: number;
  cachedInputUsdPerMillion: number;
  outputUsdPerMillion: number;
};

export type NinaExtractedReading = {
  label: string;
  value: string;
};

export type NinaProposalSource =
  | "mensagem"
  | "anexo"
  | "tarefa_existente"
  | "memoria"
  | "rotina";

export type NinaProposalPayload = {
  title: string;
  detail: string;
  owner: string;
  due_label: string;
  due_at: string | null;
  category: "home" | "bills" | "health" | "school" | "pet" | "food";
  symbol_name: string;
  amount: string;
  extracted?: NinaExtractedReading[] | null;
  rationale?: string | null;
  source?: NinaProposalSource | null;
  visibility: "private" | "shared" | null;
  confidence: number | null;
  deduplication_key: string;
};

export type NinaProposalOutput = {
  id: string;
  kind: "task" | "reminder" | "shopping" | "memory" | "seed";
  title: string;
  detail: string;
  action_title: string;
  payload: NinaProposalPayload;
};

export type NinaStructuredOutput = {
  reply: string;
  proposals: NinaProposalOutput[];
};

export type OpenAIResponsePayload = {
  id?: string;
  model?: string;
  output?: Array<Record<string, unknown>>;
  usage?: {
    input_tokens?: number;
    input_tokens_details?: {
      cached_tokens?: number;
    };
    output_tokens?: number;
    output_tokens_details?: {
      reasoning_tokens?: number;
    };
  };
  error?: {
    code?: string;
    message?: string;
  };
};

export const pricingVersion = "2026-06-15";
export const interactiveModel = "gpt-5.4-mini";
export const insightModel = "gpt-5.5";
export const insightFallbackModel = "gpt-5.4-mini";
export const maxInputTokens = 32_000;
export const maxInteractiveOutputTokens = 1_200;
export const maxInsightOutputTokens = 1_100;
export const maxToolRounds = 2;
export const maxToolCalls = 4;
export const maxInteractiveModelCalls = maxToolRounds + 1;
export const maxExtractedReadings = 4;
export const maxExtractedLabelLength = 24;
export const maxExtractedValueLength = 40;
export const maxRationaleLength = 60;

export const proposalResponseSchema = {
  type: "object",
  properties: {
    reply: {
      type: "string",
      description: "A concise and useful reply in Brazilian Portuguese.",
    },
    proposals: {
      type: "array",
      maxItems: 3,
      items: {
        type: "object",
        properties: {
          id: {
            type: "string",
            description: "A UUID generated for this proposal.",
          },
          kind: {
            type: "string",
            enum: ["task", "reminder", "shopping", "memory", "seed"],
          },
          title: { type: "string" },
          detail: { type: "string" },
          action_title: { type: "string" },
          payload: {
            type: "object",
            properties: {
              title: { type: "string" },
              detail: { type: "string" },
              owner: { type: "string" },
              due_label: { type: "string" },
              due_at: { type: ["string", "null"] },
              category: {
                type: "string",
                enum: ["home", "bills", "health", "school", "pet", "food"],
              },
              symbol_name: { type: "string" },
              amount: { type: "string" },
              extracted: {
                type: ["array", "null"],
                maxItems: maxExtractedReadings,
                items: {
                  type: "object",
                  properties: {
                    label: {
                      type: "string",
                      maxLength: maxExtractedLabelLength,
                    },
                    value: {
                      type: "string",
                      maxLength: maxExtractedValueLength,
                    },
                  },
                  required: ["label", "value"],
                  additionalProperties: false,
                },
              },
              rationale: {
                type: ["string", "null"],
                maxLength: maxRationaleLength,
                description:
                  "A short Brazilian Portuguese phrase naming what this proposal is based on.",
              },
              source: {
                type: ["string", "null"],
                enum: [
                  "mensagem",
                  "anexo",
                  "tarefa_existente",
                  "memoria",
                  "rotina",
                  null,
                ],
              },
              visibility: {
                type: ["string", "null"],
                enum: ["private", "shared", null],
              },
              confidence: {
                type: ["number", "null"],
                minimum: 0,
                maximum: 1,
              },
              deduplication_key: { type: "string" },
            },
            required: [
              "title",
              "detail",
              "owner",
              "due_label",
              "due_at",
              "category",
              "symbol_name",
              "amount",
              "extracted",
              "rationale",
              "source",
              "visibility",
              "confidence",
              "deduplication_key",
            ],
            additionalProperties: false,
          },
        },
        required: [
          "id",
          "kind",
          "title",
          "detail",
          "action_title",
          "payload",
        ],
        additionalProperties: false,
      },
    },
  },
  required: ["reply", "proposals"],
  additionalProperties: false,
} as const;

export const insightResponseSchema = {
  type: "object",
  properties: {
    insights: {
      type: "array",
      minItems: 1,
      maxItems: 4,
      items: {
        type: "object",
        properties: {
          title: { type: "string" },
          message: { type: "string" },
          metric: { type: "string" },
          symbol_name: { type: "string" },
          tone: {
            type: "string",
            enum: ["mint", "coral", "sky", "amber", "lavender"],
          },
        },
        required: ["title", "message", "metric", "symbol_name", "tone"],
        additionalProperties: false,
      },
    },
  },
  required: ["insights"],
  additionalProperties: false,
} as const;

export function parsePositiveNumber(
  rawValue: string | undefined,
  fallback: number,
): number {
  const parsed = Number(rawValue);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : fallback;
}

export function pricingForModel(
  model: string,
  env: Record<string, string | undefined> = {},
): ModelPricing {
  if (model === "gpt-5.5") {
    return {
      inputUsdPerMillion: parsePositiveNumber(
        env.NINA_GPT_5_5_INPUT_USD_PER_M,
        5,
      ),
      cachedInputUsdPerMillion: parsePositiveNumber(
        env.NINA_GPT_5_5_CACHED_INPUT_USD_PER_M,
        0.5,
      ),
      outputUsdPerMillion: parsePositiveNumber(
        env.NINA_GPT_5_5_OUTPUT_USD_PER_M,
        30,
      ),
    };
  }

  return {
    inputUsdPerMillion: parsePositiveNumber(
      env.NINA_GPT_5_4_MINI_INPUT_USD_PER_M,
      0.75,
    ),
    cachedInputUsdPerMillion: parsePositiveNumber(
      env.NINA_GPT_5_4_MINI_CACHED_INPUT_USD_PER_M,
      0.075,
    ),
    outputUsdPerMillion: parsePositiveNumber(
      env.NINA_GPT_5_4_MINI_OUTPUT_USD_PER_M,
      4.5,
    ),
  };
}

export function estimateMaximumCostMicrousd(
  inputTokens: number,
  maxOutputTokens: number,
  pricing: ModelPricing,
): number {
  const usd = (
    Math.max(inputTokens, 0) * pricing.inputUsdPerMillion
    + Math.max(maxOutputTokens, 0) * pricing.outputUsdPerMillion
  ) / 1_000_000;

  return Math.ceil(usd * 1_000_000);
}

export function estimateInteractiveReservationMicrousd(
  pricing: ModelPricing,
): number {
  return estimateMaximumCostMicrousd(
    maxInputTokens * maxInteractiveModelCalls,
    maxInteractiveOutputTokens * maxInteractiveModelCalls,
    pricing,
  );
}

export function estimateInsightReservationMicrousd(
  inputTokens: number,
  env: Record<string, string | undefined> = {},
): number {
  return estimateMaximumCostMicrousd(
    inputTokens,
    maxInsightOutputTokens,
    pricingForModel(insightModel, env),
  ) + estimateMaximumCostMicrousd(
    inputTokens,
    maxInsightOutputTokens,
    pricingForModel(insightFallbackModel, env),
  );
}

export function addUsage(left: NinaUsage, right: NinaUsage): NinaUsage {
  return {
    inputTokens: left.inputTokens + right.inputTokens,
    cachedInputTokens: left.cachedInputTokens + right.cachedInputTokens,
    outputTokens: left.outputTokens + right.outputTokens,
    reasoningTokens: left.reasoningTokens + right.reasoningTokens,
  };
}

export function emptyUsage(): NinaUsage {
  return {
    inputTokens: 0,
    cachedInputTokens: 0,
    outputTokens: 0,
    reasoningTokens: 0,
  };
}

export function calculateActualCostMicrousd(
  usage: NinaUsage,
  pricing: ModelPricing,
): number {
  const cachedTokens = Math.min(
    Math.max(usage.cachedInputTokens, 0),
    Math.max(usage.inputTokens, 0),
  );
  const uncachedTokens = Math.max(usage.inputTokens - cachedTokens, 0);
  const usd = (
    uncachedTokens * pricing.inputUsdPerMillion
    + cachedTokens * pricing.cachedInputUsdPerMillion
    + Math.max(usage.outputTokens, 0) * pricing.outputUsdPerMillion
  ) / 1_000_000;

  return Math.ceil(usd * 1_000_000);
}

export function usageFromResponse(payload: OpenAIResponsePayload): NinaUsage {
  return {
    inputTokens: payload.usage?.input_tokens ?? 0,
    cachedInputTokens:
      payload.usage?.input_tokens_details?.cached_tokens ?? 0,
    outputTokens: payload.usage?.output_tokens ?? 0,
    reasoningTokens:
      payload.usage?.output_tokens_details?.reasoning_tokens ?? 0,
  };
}

export function extractOutputText(
  payload: OpenAIResponsePayload,
): string | null {
  for (const item of payload.output ?? []) {
    if (item.type !== "message" || !Array.isArray(item.content)) continue;

    for (const content of item.content as Array<Record<string, unknown>>) {
      if (
        content.type === "output_text"
        && typeof content.text === "string"
        && content.text.length > 0
      ) {
        return content.text;
      }
    }
  }

  return null;
}

export function functionCalls(
  payload: OpenAIResponsePayload,
): Array<{
  callId: string;
  name: string;
  arguments: string;
}> {
  return (payload.output ?? []).flatMap((item) => {
    if (
      item.type !== "function_call"
      || typeof item.call_id !== "string"
      || typeof item.name !== "string"
      || typeof item.arguments !== "string"
    ) {
      return [];
    }

    return [{
      callId: item.call_id,
      name: item.name,
      arguments: item.arguments,
    }];
  });
}

function isExtractedReadings(value: unknown): boolean {
  if (value === null || value === undefined) return true;
  if (!Array.isArray(value) || value.length > maxExtractedReadings) {
    return false;
  }

  return value.every((entry) => {
    if (!entry || typeof entry !== "object") return false;
    const reading = entry as Partial<NinaExtractedReading>;
    return typeof reading.label === "string"
      && reading.label.length > 0
      && reading.label.length <= maxExtractedLabelLength
      && typeof reading.value === "string"
      && reading.value.length > 0
      && reading.value.length <= maxExtractedValueLength;
  });
}

function isProposalRationale(value: unknown): boolean {
  if (value === null || value === undefined) return true;
  return typeof value === "string"
    && value.trim().length > 0
    && value.length <= maxRationaleLength;
}

function isProposalSource(value: unknown): boolean {
  if (value === null || value === undefined) return true;
  return typeof value === "string"
    && ["mensagem", "anexo", "tarefa_existente", "memoria", "rotina"].includes(
      value,
    );
}

export function isStructuredOutput(
  value: unknown,
): value is NinaStructuredOutput {
  if (!value || typeof value !== "object") return false;
  const output = value as Partial<NinaStructuredOutput>;

  return typeof output.reply === "string"
    && Array.isArray(output.proposals)
    && output.proposals.length <= 3
    && output.proposals.every((proposal) =>
      proposal
      && typeof proposal.id === "string"
      && typeof proposal.kind === "string"
      && ["task", "reminder", "shopping", "memory", "seed"].includes(
        proposal.kind,
      )
      && typeof proposal.title === "string"
      && typeof proposal.detail === "string"
      && typeof proposal.action_title === "string"
      && proposal.payload
      && typeof proposal.payload === "object"
      && typeof proposal.payload.title === "string"
      && typeof proposal.payload.detail === "string"
      && typeof proposal.payload.owner === "string"
      && typeof proposal.payload.due_label === "string"
      && (
        proposal.payload.due_at === null
        || typeof proposal.payload.due_at === "string"
      )
      && ["home", "bills", "health", "school", "pet", "food"].includes(
        proposal.payload.category,
      )
      && typeof proposal.payload.symbol_name === "string"
      && typeof proposal.payload.amount === "string"
      && isExtractedReadings(proposal.payload.extracted)
      && isProposalRationale(proposal.payload.rationale)
      && isProposalSource(proposal.payload.source)
      && (
        proposal.payload.visibility === null
        || proposal.payload.visibility === "private"
        || proposal.payload.visibility === "shared"
      )
      && (
        proposal.payload.confidence === null
        || (
          typeof proposal.payload.confidence === "number"
          && proposal.payload.confidence >= 0
          && proposal.payload.confidence <= 1
        )
      )
      && typeof proposal.payload.deduplication_key === "string"
    );
}

export function isToolCallBatchAllowed(
  round: number,
  totalToolCalls: number,
  requestedCalls: number,
): boolean {
  return round < maxToolRounds
    && requestedCalls >= 0
    && totalToolCalls + requestedCalls <= maxToolCalls;
}

export function legacySuggestionFromProposal(
  proposal: NinaProposalOutput | undefined,
): Record<string, unknown> | null {
  if (!proposal || (proposal.kind !== "task" && proposal.kind !== "reminder")) {
    return null;
  }

  return {
    title: proposal.title,
    detail: proposal.detail,
    action_title: proposal.action_title,
    kind: proposal.kind,
    payload_title: proposal.payload.title,
    payload_detail: proposal.payload.detail,
    payload_owner: proposal.payload.owner,
    payload_due_label: proposal.payload.due_label,
    category: proposal.payload.category,
    symbol_name: proposal.payload.symbol_name,
  };
}

export function legacySuggestionFromProposals(
  proposals: NinaProposalOutput[],
): Record<string, unknown> | null {
  const compatible = proposals.find((proposal) =>
    proposal.kind === "task" || proposal.kind === "reminder"
  );
  return legacySuggestionFromProposal(compatible);
}

export function safeErrorCode(value: unknown): string {
  if (!value || typeof value !== "object") return "unknown_error";
  const code = (value as { error?: { code?: unknown } }).error?.code;
  return typeof code === "string" && code.length > 0
    ? code.slice(0, 120)
    : "unknown_error";
}

export function shouldUseInsightFallback(
  status: number,
  payload: OpenAIResponsePayload,
): boolean {
  const code = safeErrorCode(payload);
  return status === 404
    || code === "model_not_found"
    || code === "unsupported_model"
    || code === "invalid_model";
}

export function environmentPricing(): Record<string, string | undefined> {
  return {
    NINA_GPT_5_5_INPUT_USD_PER_M:
      Deno.env.get("NINA_GPT_5_5_INPUT_USD_PER_M"),
    NINA_GPT_5_5_CACHED_INPUT_USD_PER_M:
      Deno.env.get("NINA_GPT_5_5_CACHED_INPUT_USD_PER_M"),
    NINA_GPT_5_5_OUTPUT_USD_PER_M:
      Deno.env.get("NINA_GPT_5_5_OUTPUT_USD_PER_M"),
    NINA_GPT_5_4_MINI_INPUT_USD_PER_M:
      Deno.env.get("NINA_GPT_5_4_MINI_INPUT_USD_PER_M"),
    NINA_GPT_5_4_MINI_CACHED_INPUT_USD_PER_M:
      Deno.env.get("NINA_GPT_5_4_MINI_CACHED_INPUT_USD_PER_M"),
    NINA_GPT_5_4_MINI_OUTPUT_USD_PER_M:
      Deno.env.get("NINA_GPT_5_4_MINI_OUTPUT_USD_PER_M"),
  };
}
