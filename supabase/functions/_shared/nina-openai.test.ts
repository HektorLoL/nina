import {
  assert,
  assertEquals,
  assertFalse,
  assertRejects,
  assertStringIncludes,
} from "@std/assert";
import {
  failureCode,
  insightTexts,
  minimumOpenAIAttemptMs,
  moderate,
  moderationModel,
  moderationTexts,
  type NinaDeadline,
  ninaDeadline,
  NinaFailure,
  ninaFailureCodes,
  ninaTurnBudgetMs,
  openAIRetryBackoffMs,
  type OpenAITransport,
  postOpenAI,
  upstreamFailure,
  upstreamStatus,
} from "./nina-openai.ts";

type Exchange = {
  url: string;
  body: unknown;
  timeoutMs: number;
};

type Scripted =
  | { status: number; body: string }
  | { throws: unknown };

function jsonBody(value: unknown): string {
  return JSON.stringify(value);
}

class ScriptedTransport implements OpenAITransport {
  readonly exchanges: Exchange[] = [];
  readonly sleeps: number[] = [];
  private pendingTimeout = 0;

  constructor(
    private readonly script: Scripted[],
    private readonly clock?: { now: number },
  ) {}

  fetch = (url: string, init: RequestInit): Promise<Response> => {
    this.exchanges.push({
      url,
      body: JSON.parse(String(init.body)),
      timeoutMs: this.pendingTimeout,
    });
    const next = this.script.shift();
    if (!next) throw new Error("unscripted request");
    if ("throws" in next) return Promise.reject(next.throws);
    return Promise.resolve(new Response(next.body, { status: next.status }));
  };

  sleep = (milliseconds: number): Promise<void> => {
    this.sleeps.push(milliseconds);
    if (this.clock) this.clock.now += milliseconds;
    return Promise.resolve();
  };

  signal = (milliseconds: number): AbortSignal => {
    this.pendingTimeout = milliseconds;
    return new AbortController().signal;
  };
}

function deadlineAt(remaining: number): {
  clock: { now: number };
  deadline: NinaDeadline;
} {
  const clock = { now: 1_000 };
  return {
    clock,
    deadline: ninaDeadline(clock.now, remaining, () => clock.now),
  };
}

const usage = { usage: { input_tokens: 100, output_tokens: 20 } };

Deno.test("a 429 or a 5xx is retried once after a short pause, and every answer is kept for booking", async () => {
  for (const status of [429, 500, 502, 503]) {
    const transport = new ScriptedTransport([
      { status, body: jsonBody({ error: { code: "busy" }, ...usage }) },
      { status: 200, body: jsonBody({ id: "resp_2", ...usage }) },
    ]);
    const answer = await postOpenAI(
      "/v1/responses",
      "sk-test",
      { model: "gpt-6-luna" },
      { timeoutMs: 35_000, transport },
    );

    assert(answer.ok, String(status));
    assertEquals(answer.status, 200);
    assertEquals(answer.payload.id, "resp_2");
    assertEquals(answer.answers.length, 2);
    assertEquals(transport.exchanges.length, 2);
    assertEquals(transport.sleeps, [openAIRetryBackoffMs]);
    assertEquals(
      transport.exchanges.map((exchange) => exchange.url),
      [
        "https://api.openai.com/v1/responses",
        "https://api.openai.com/v1/responses",
      ],
    );
  }
});

Deno.test("a second 429 or 5xx is answered as it came, never retried again", async () => {
  const transport = new ScriptedTransport([
    { status: 503, body: "<html>Bad gateway</html>" },
    { status: 503, body: "<html>Bad gateway</html>" },
  ]);
  const answer = await postOpenAI("/v1/responses", "sk-test", {}, {
    timeoutMs: 35_000,
    transport,
  });

  assertFalse(answer.ok);
  assertEquals(answer.status, 503);
  assertEquals(answer.payload, {});
  assertEquals(answer.answers, [{}, {}]);
  assertEquals(transport.exchanges.length, 2);
  assertEquals(transport.sleeps.length, 1);
});

Deno.test("a refusal that is not a 429 or a 5xx is never retried", async () => {
  for (const status of [400, 401, 404, 413]) {
    const transport = new ScriptedTransport([
      { status, body: jsonBody({ error: { code: "invalid_parameter" } }) },
    ]);
    const answer = await postOpenAI("/v1/responses", "sk-test", {}, {
      timeoutMs: 35_000,
      transport,
    });

    assertFalse(answer.ok);
    assertEquals(answer.status, status);
    assertEquals(transport.exchanges.length, 1);
    assertEquals(transport.sleeps, []);
  }
});

Deno.test("no attempt outlives the turn's deadline, and none starts without a second left", async () => {
  const { clock, deadline } = deadlineAt(50_000);
  const transport = new ScriptedTransport([
    { status: 200, body: jsonBody({}) },
    { status: 200, body: jsonBody({}) },
  ], clock);

  await postOpenAI("/v1/responses", "sk-test", {}, {
    timeoutMs: 35_000,
    deadline,
    transport,
  });
  clock.now += 30_000;
  await postOpenAI("/v1/responses", "sk-test", {}, {
    timeoutMs: 35_000,
    deadline,
    transport,
  });
  assertEquals(
    transport.exchanges.map((exchange) => exchange.timeoutMs),
    [35_000, 20_000],
  );

  clock.now += 20_000 - minimumOpenAIAttemptMs + 1;
  const late = await assertRejects(
    () =>
      postOpenAI("/v1/responses", "sk-test", {}, {
        timeoutMs: 35_000,
        deadline,
        transport,
      }),
    NinaFailure,
  );
  assertEquals(late.code, "turn_deadline_exceeded");
  assertEquals(transport.exchanges.length, 2);
});

Deno.test("a retry waits only while the deadline still leaves it room", async () => {
  const roomy = deadlineAt(minimumOpenAIAttemptMs + openAIRetryBackoffMs);
  const retried = new ScriptedTransport([
    { status: 429, body: jsonBody({}) },
    { status: 200, body: jsonBody({ id: "resp_retry" }) },
  ], roomy.clock);
  const answer = await postOpenAI("/v1/responses", "sk-test", {}, {
    timeoutMs: 35_000,
    deadline: roomy.deadline,
    transport: retried,
  });
  assertEquals(answer.payload.id, "resp_retry");
  assertEquals(
    retried.exchanges.map((exchange) => exchange.timeoutMs),
    [minimumOpenAIAttemptMs + openAIRetryBackoffMs, minimumOpenAIAttemptMs],
  );

  const tight = deadlineAt(minimumOpenAIAttemptMs + openAIRetryBackoffMs - 1);
  const notRetried = new ScriptedTransport([
    { status: 429, body: jsonBody({}) },
  ], tight.clock);
  const refused = await postOpenAI("/v1/responses", "sk-test", {}, {
    timeoutMs: 35_000,
    deadline: tight.deadline,
    transport: notRetried,
  });
  assertEquals(refused.status, 429);
  assertEquals(notRetried.exchanges.length, 1);
  assertEquals(notRetried.sleeps, []);
});

Deno.test("a timeout or a dropped connection becomes a fixed code, never the error's own words", async () => {
  for (
    const [thrown, code] of [
      [
        new DOMException("The signal has been aborted", "TimeoutError"),
        "openai_timeout",
      ],
      [new DOMException("aborted", "AbortError"), "openai_timeout"],
      [
        new TypeError("error sending request for url (https://api.openai.com)"),
        "openai_unreachable",
      ],
    ] as const
  ) {
    const transport = new ScriptedTransport([{ throws: thrown }]);
    const failure = await assertRejects(
      () =>
        postOpenAI("/v1/responses", "sk-test", {}, {
          timeoutMs: 35_000,
          transport,
        }),
      NinaFailure,
    );
    assertEquals(failure.code, code);
    assertEquals(failure.message, code);
    assertEquals(transport.exchanges.length, 1);
  }
});

Deno.test("only a code from the closed list leaves a failure, whatever the error says", () => {
  let parseError: unknown;
  try {
    JSON.parse('{"reply": "A Lia tem consulta amanhã" oops');
  } catch (error) {
    parseError = error;
  }
  assert(parseError instanceof SyntaxError);
  assertEquals(failureCode(parseError), "unknown_error");
  assertEquals(failureCode(new Error("Ana Souza")), "unknown_error");
  assertEquals(failureCode("persistence_failed"), "unknown_error");
  assertEquals(
    failureCode(new NinaFailure("persistence_failed")),
    "persistence_failed",
  );
  for (const code of ninaFailureCodes) {
    assert(/^[a-z_]+$/.test(code), code);
  }

  assertEquals(failureCode(upstreamFailure(429)), "openai_rate_limited");
  assertEquals(failureCode(upstreamFailure(500)), "openai_server_error");
  assertEquals(failureCode(upstreamFailure(504)), "openai_server_error");
  assertEquals(failureCode(upstreamFailure(400)), "openai_request_rejected");
  assertEquals(upstreamStatus(upstreamFailure(404)), 404);
  assertEquals(upstreamStatus(new NinaFailure("openai_timeout")), null);
  assertEquals(upstreamStatus(new Error("x")), null);
});

Deno.test("moderation names its model, reads a verdict and fails closed on any answer without one", async () => {
  const clean = new ScriptedTransport([
    {
      status: 200,
      body: jsonBody({ results: [{ flagged: false, categories: {} }] }),
    },
  ]);
  assertEquals(
    await moderate("sk-test", [{ type: "text", text: "Comprar leite" }], {
      transport: clean,
    }),
    { flagged: false, sexualMinors: false, selfHarm: false },
  );
  assertEquals(clean.exchanges[0].url, "https://api.openai.com/v1/moderations");
  assertEquals(clean.exchanges[0].body, {
    model: moderationModel,
    input: [{ type: "text", text: "Comprar leite" }],
  });
  assertEquals(moderationModel, "omni-moderation-latest");
  assertEquals(clean.exchanges[0].timeoutMs, 15_000);

  const flagged = new ScriptedTransport([
    {
      status: 200,
      body: jsonBody({
        results: [{ flagged: true, categories: { violence: true } }],
      }),
    },
  ]);
  assert(
    (await moderate("sk-test", [{ type: "text", text: "x" }], {
      transport: flagged,
    })).flagged,
  );

  for (
    const script of [
      [{ status: 400, body: jsonBody({ error: { code: "bad" } }) }],
      [{ status: 200, body: jsonBody({}) }],
      [{ status: 200, body: jsonBody({ results: [] }) }],
      [{ status: 200, body: "not json" }],
      [
        { status: 503, body: "" },
        { status: 503, body: "" },
      ],
    ]
  ) {
    const failure = await assertRejects(
      () =>
        moderate("sk-test", [{ type: "text", text: "x" }], {
          transport: new ScriptedTransport(script),
        }),
      NinaFailure,
    );
    assertEquals(failure.code, "moderation_unavailable");
  }

  const silent = new ScriptedTransport([]);
  assertEquals(await moderate("sk-test", [], { transport: silent }), {
    flagged: false,
    sexualMinors: false,
    selfHarm: false,
  });
  assertEquals(silent.exchanges.length, 0);
});

Deno.test("every insight line is moderated, and nothing that is not text is sent", () => {
  assertEquals(
    moderationTexts(
      insightTexts([
        {
          title: "Semana leve",
          message: "A casa fechou 8 tarefas.",
          metric: "8 feitas",
          symbol_name: "checkmark",
          tone: "mint",
        },
        null,
        { title: "  ", message: 3, metric: "1 aberta" },
      ]),
    ),
    [
      { type: "text", text: "Semana leve" },
      { type: "text", text: "A casa fechou 8 tarefas." },
      { type: "text", text: "8 feitas" },
      { type: "text", text: "1 aberta" },
    ],
  );
});

Deno.test("the turn budget ends well before the app lets go of a lost turn", async () => {
  const appStore = await Deno.readTextFile(
    new URL("../../../Nina/AppStore.swift", import.meta.url),
  );
  const window = appStore.match(
    /lostTurnMayStillBeRunning\(sentAt: Date, now: Date\) -> Bool \{\s*now\.timeIntervalSince\(sentAt\) < (\d+)/,
  );
  assert(window, "the app's lost-turn window");
  assertEquals(ninaTurnBudgetMs, 50_000);
  assert(ninaTurnBudgetMs * 2 < Number(window[1]) * 1_000);
});

Deno.test("the chat and the insight reach OpenAI only through the shared transport, the chat within its deadline, and log only fixed codes", async () => {
  const chat = await Deno.readTextFile(
    new URL("../nina-chat/index.ts", import.meta.url),
  );
  const maintenance = await Deno.readTextFile(
    new URL("../nina-maintenance/index.ts", import.meta.url),
  );
  const handler = chat.slice(chat.indexOf("Deno.serve("));

  for (const source of [chat, maintenance]) {
    assertFalse(source.includes("https://api.openai.com"));
    assertFalse(source.includes("await fetch("));
    assertFalse(source.includes(".message.slice("));
    assertFalse(source.includes("safeErrorCode("));
    assertStringIncludes(source, "failureCode(");
  }
  assertStringIncludes(
    handler,
    "const turnDeadline = ninaDeadline(startedAt);",
  );
  assertEquals(
    [...handler.matchAll(/openAIJSON\(\s*"[^"]+",[\s\S]*?\n\s*\);/g)].filter(
      (call) => !call[0].includes("turnDeadline"),
    ),
    [],
  );
  assertEquals(
    [...handler.matchAll(/openAIJSON\(/g)].length,
    3,
  );
  assertStringIncludes(
    handler,
    "await moderateInput(openAIKey, modelMessage, body, turnDeadline)",
  );
  assertStringIncludes(handler, "}, turnDeadline);");
  assertStringIncludes(handler, "for (const received of answer.answers)");
  assertStringIncludes(
    handler,
    'try {\n      structured = JSON.parse(outputText);\n    } catch {\n      throw new NinaFailure("invalid_assistant_response");',
  );
});
