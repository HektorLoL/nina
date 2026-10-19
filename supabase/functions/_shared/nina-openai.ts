import {
  type ModerationVerdict,
  moderationVerdict,
  type OpenAIResponsePayload,
} from "./nina-ai.ts";

export const openAIBaseURL = "https://api.openai.com";
export const moderationModel = "omni-moderation-latest";
export const ninaTurnBudgetMs = 50_000;
export const openAIRetryBackoffMs = 500;
export const minimumOpenAIAttemptMs = 1_000;
export const moderationTimeoutMs = 15_000;

export const ninaFailureCodes = [
  "turn_deadline_exceeded",
  "openai_timeout",
  "openai_unreachable",
  "openai_rate_limited",
  "openai_server_error",
  "openai_request_rejected",
  "token_count_unavailable",
  "input_too_large",
  "tool_limit_exceeded",
  "missing_final_response",
  "invalid_assistant_response",
  "moderation_unavailable",
  "insight_moderated",
  "persistence_failed",
  "unknown_error",
] as const;

export type NinaFailureCode = typeof ninaFailureCodes[number];

export class NinaFailure extends Error {
  constructor(
    readonly code: NinaFailureCode,
    readonly upstreamStatus: number | null = null,
  ) {
    super(code);
    this.name = "NinaFailure";
  }
}

// Only a code from the closed list reaches a log line or a run row: an
// error's own message can quote what the model or the provider wrote.
export function failureCode(error: unknown): NinaFailureCode {
  return error instanceof NinaFailure ? error.code : "unknown_error";
}

export function upstreamStatus(error: unknown): number | null {
  return error instanceof NinaFailure ? error.upstreamStatus : null;
}

export function upstreamFailure(status: number): NinaFailure {
  if (status === 429) return new NinaFailure("openai_rate_limited", status);
  if (status >= 500) return new NinaFailure("openai_server_error", status);
  return new NinaFailure("openai_request_rejected", status);
}

export type NinaDeadline = {
  readonly endsAt: number;
  readonly now: () => number;
};

export function ninaDeadline(
  startedAt: number,
  budgetMs: number = ninaTurnBudgetMs,
  now: () => number = () => performance.now(),
): NinaDeadline {
  return { endsAt: startedAt + budgetMs, now };
}

export function remainingMs(deadline: NinaDeadline): number {
  return deadline.endsAt - deadline.now();
}

export type OpenAITransport = {
  fetch: (url: string, init: RequestInit) => Promise<Response>;
  sleep: (milliseconds: number) => Promise<void>;
  signal: (milliseconds: number) => AbortSignal;
};

export const defaultOpenAITransport: OpenAITransport = {
  fetch: (url, init) => fetch(url, init),
  sleep: (milliseconds) =>
    new Promise((resolve) => setTimeout(resolve, milliseconds)),
  signal: (milliseconds) => AbortSignal.timeout(milliseconds),
};

export type OpenAIRequestOptions = {
  timeoutMs: number;
  deadline?: NinaDeadline;
  transport?: OpenAITransport;
};

export type OpenAIAnswer = {
  ok: boolean;
  status: number;
  payload: OpenAIResponsePayload;
  answers: OpenAIResponsePayload[];
};

export function isRetryableStatus(status: number): boolean {
  return status === 429 || status >= 500;
}

function attemptTimeoutMs(
  timeoutMs: number,
  deadline: NinaDeadline | undefined,
): number | null {
  if (!deadline) return timeoutMs;
  const remaining = remainingMs(deadline);
  if (remaining < minimumOpenAIAttemptMs) return null;
  return Math.min(timeoutMs, Math.floor(remaining));
}

function mayRetry(deadline: NinaDeadline | undefined): boolean {
  return !deadline ||
    remainingMs(deadline) - openAIRetryBackoffMs >= minimumOpenAIAttemptMs;
}

function transportFailure(error: unknown): NinaFailure {
  const timedOut = error instanceof DOMException &&
    (error.name === "TimeoutError" || error.name === "AbortError");
  return new NinaFailure(timedOut ? "openai_timeout" : "openai_unreachable");
}

async function readPayload(response: Response): Promise<OpenAIResponsePayload> {
  const text = await response.text();
  try {
    const parsed = JSON.parse(text) as unknown;
    return parsed && typeof parsed === "object"
      ? parsed as OpenAIResponsePayload
      : {};
  } catch {
    return {};
  }
}

// One retry after a 429 or a 5xx, and only while the turn's deadline leaves
// room for it, so no turn outlives its budget by retrying.
export async function postOpenAI(
  path: string,
  apiKey: string,
  body: Record<string, unknown>,
  options: OpenAIRequestOptions,
): Promise<OpenAIAnswer> {
  const transport = options.transport ?? defaultOpenAITransport;
  const answers: OpenAIResponsePayload[] = [];

  for (let attempt = 0;; attempt += 1) {
    const timeoutMs = attemptTimeoutMs(options.timeoutMs, options.deadline);
    if (timeoutMs === null) throw new NinaFailure("turn_deadline_exceeded");

    let response: Response;
    let payload: OpenAIResponsePayload;
    try {
      response = await transport.fetch(`${openAIBaseURL}${path}`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
        signal: transport.signal(timeoutMs),
      });
      payload = await readPayload(response);
    } catch (error) {
      throw transportFailure(error);
    }
    answers.push(payload);

    if (
      attempt === 0 && isRetryableStatus(response.status) &&
      mayRetry(options.deadline)
    ) {
      await transport.sleep(openAIRetryBackoffMs);
      continue;
    }

    return { ok: response.ok, status: response.status, payload, answers };
  }
}

export type ModerationInput = Record<string, unknown>;

// A moderation answer that names no result is no verdict, so the turn fails
// closed instead of reading it as clean.
export async function moderate(
  apiKey: string,
  inputs: ModerationInput[],
  options: Partial<OpenAIRequestOptions> = {},
): Promise<ModerationVerdict> {
  if (inputs.length === 0) {
    return { flagged: false, sexualMinors: false, selfHarm: false };
  }

  const answer = await postOpenAI(
    "/v1/moderations",
    apiKey,
    { model: moderationModel, input: inputs },
    { ...options, timeoutMs: options.timeoutMs ?? moderationTimeoutMs },
  );
  const results = (answer.payload as { results?: unknown }).results;
  if (!answer.ok || !Array.isArray(results) || results.length === 0) {
    throw new NinaFailure(
      "moderation_unavailable",
      answer.ok ? null : answer.status,
    );
  }

  return moderationVerdict(answer.payload);
}

export function moderationTexts(texts: unknown[]): ModerationInput[] {
  return texts
    .filter((text): text is string =>
      typeof text === "string" && text.trim().length > 0
    )
    .map((text) => ({ type: "text", text }));
}

export function insightTexts(insights: unknown[]): unknown[] {
  return insights.flatMap((insight) => {
    if (!insight || typeof insight !== "object") return [];
    const entry = insight as Record<string, unknown>;
    return [entry.title, entry.message, entry.metric];
  });
}
