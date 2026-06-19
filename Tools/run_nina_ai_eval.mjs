#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

const projectRef = process.argv[2] ?? "apemftmlsjocvifbptum";
const projectURL = `https://${projectRef}.supabase.co`;
const fixturePath = resolve("supabase/functions/nina-chat/evals/pt-BR.json");
const reportPath = resolve(
  "supabase/functions/nina-chat/evals/latest-report.json",
);
const privateMarker = `SEGREDO-PRIVADO-${crypto.randomUUID()}`;
const password = `NinaEval-${crypto.randomUUID()}-aA1!`;
const createdUserIDs = [];
let familyID = null;
let restoreEmailAuth = false;
let managementToken = "";

function run(command, args) {
  return execFileSync(command, args, {
    cwd: process.cwd(),
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  }).trim();
}

function requireValue(value, label) {
  if (!value) throw new Error(`missing_${label}`);
  return value;
}

async function request(url, options = {}) {
  const response = await fetch(url, options);
  const text = await response.text();
  let payload = null;

  if (text) {
    try {
      payload = JSON.parse(text);
    } catch {
      payload = text;
    }
  }

  if (!response.ok) {
    const error = new Error(
      `${options.method ?? "GET"} ${url} failed (${response.status})`,
    );
    error.status = response.status;
    error.payload = payload;
    throw error;
  }

  return { response, payload };
}

function adminHeaders(serviceRole, extra = {}) {
  return {
    apikey: serviceRole,
    Authorization: `Bearer ${serviceRole}`,
    "Content-Type": "application/json",
    ...extra,
  };
}

function userHeaders(apiKey, accessToken, extra = {}) {
  return {
    apikey: apiKey,
    Authorization: `Bearer ${accessToken}`,
    "Content-Type": "application/json",
    ...extra,
  };
}

async function insertRows(serviceRole, table, rows) {
  return await request(`${projectURL}/rest/v1/${table}`, {
    method: "POST",
    headers: adminHeaders(serviceRole, {
      Prefer: "return=representation",
    }),
    body: JSON.stringify(rows),
  });
}

async function countRows(serviceRole, table) {
  const { response } = await request(
    `${projectURL}/rest/v1/${table}?select=id&family_id=eq.${familyID}`,
    {
      method: "HEAD",
      headers: adminHeaders(serviceRole, {
        Prefer: "count=exact",
      }),
    },
  );
  const range = response.headers.get("content-range") ?? "*/0";
  return Number(range.split("/").at(-1) ?? 0);
}

async function mutableCounts(serviceRole) {
  const tables = ["tasks", "reminders", "shopping_items", "memory_items"];
  const values = await Promise.all(
    tables.map((table) => countRows(serviceRole, table)),
  );
  return Object.fromEntries(tables.map((table, index) => [table, values[index]]));
}

function multisetEquals(left, right) {
  return [...left].sort().join("|") === [...right].sort().join("|");
}

function isUUID(value) {
  return typeof value === "string"
    && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value);
}

function schemaIsValid(payload) {
  return payload?.version === 2
    && isUUID(payload.run_id)
    && isUUID(payload.thread_id)
    && isUUID(payload.assistant_message_id)
    && typeof payload.reply === "string"
    && Array.isArray(payload.proposals)
    && payload.proposals.length <= 3
    && payload.proposals.every((proposal) =>
      isUUID(proposal?.id)
      && ["task", "reminder", "shopping", "memory"].includes(proposal?.kind)
      && proposal?.state === "pending"
      && typeof proposal?.title === "string"
      && typeof proposal?.detail === "string"
      && typeof proposal?.action_title === "string"
      && proposal?.payload
      && typeof proposal.payload === "object"
    );
}

function median(values) {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const midpoint = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 0
    ? (sorted[midpoint - 1] + sorted[midpoint]) / 2
    : sorted[midpoint];
}

async function createUser(serviceRole, email, name) {
  const { payload } = await request(`${projectURL}/auth/v1/admin/users`, {
    method: "POST",
    headers: adminHeaders(serviceRole),
    body: JSON.stringify({
      email,
      password,
      email_confirm: true,
      user_metadata: { display_name: name },
    }),
  });
  createdUserIDs.push(payload.id);
  return payload;
}

async function signIn(apiKey, email) {
  const { payload } = await request(
    `${projectURL}/auth/v1/token?grant_type=password`,
    {
      method: "POST",
      headers: {
        apikey: apiKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ email, password }),
    },
  );
  return requireValue(payload.access_token, "access_token");
}

async function deletePrivateHistory(apiKey, accessToken) {
  await request(`${projectURL}/rest/v1/rpc/delete_current_nina_chat_history`, {
    method: "POST",
    headers: userHeaders(apiKey, accessToken),
    body: JSON.stringify({ target_family_id: familyID }),
  });
}

async function fetchRun(serviceRole, runID) {
  const { payload } = await request(
    `${projectURL}/rest/v1/nina_ai_runs?id=eq.${runID}&select=status,actual_microusd,input_tokens,output_tokens,error_code`,
    { headers: adminHeaders(serviceRole) },
  );
  return payload[0] ?? null;
}

async function configureEmailAuth(enabled) {
  await request(
    `https://api.supabase.com/v1/projects/${projectRef}/config/auth`,
    {
      method: "PATCH",
      headers: {
        Authorization: `Bearer ${managementToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ external_email_enabled: enabled }),
    },
  );
}

async function cleanup(serviceRole) {
  if (familyID) {
    await fetch(`${projectURL}/rest/v1/families?id=eq.${familyID}`, {
      method: "DELETE",
      headers: adminHeaders(serviceRole),
    });
  }

  for (const userID of createdUserIDs) {
    await fetch(`${projectURL}/auth/v1/admin/users/${userID}`, {
      method: "DELETE",
      headers: adminHeaders(serviceRole),
    });
  }

  if (restoreEmailAuth && managementToken) {
    await configureEmailAuth(false);
  }
}

const fixture = JSON.parse(await readFile(fixturePath, "utf8"));
const apiKeys = JSON.parse(
  run("npx", [
    "-y",
    "supabase",
    "projects",
    "api-keys",
    "--project-ref",
    projectRef,
    "--output",
    "json",
  ]),
);
const apiKey = requireValue(
  apiKeys.find((key) => key.type === "publishable")?.api_key
    ?? apiKeys.find((key) => key.name === "anon")?.api_key,
  "publishable_key",
);
const serviceRole = requireValue(
  apiKeys.find((key) => key.name === "service_role")?.api_key,
  "service_role_key",
);

try {
  managementToken = run("security", [
    "find-generic-password",
    "-s",
    "Supabase CLI",
    "-w",
  ]);
  const { payload: authConfig } = await request(
    `https://api.supabase.com/v1/projects/${projectRef}/config/auth`,
    {
      headers: { Authorization: `Bearer ${managementToken}` },
    },
  );
  restoreEmailAuth = authConfig.external_email_enabled !== true;
  if (restoreEmailAuth) {
    await configureEmailAuth(true);
    await new Promise((resolveDelay) => setTimeout(resolveDelay, 5_000));
  }

  const suffix = crypto.randomUUID().slice(0, 8);
  const firstEmail = `nina-eval-${suffix}-a@example.com`;
  const secondEmail = `nina-eval-${suffix}-b@example.com`;
  const firstUser = await createUser(serviceRole, firstEmail, "Heitor Eval");
  const secondUser = await createUser(serviceRole, secondEmail, "Mirna Eval");
  familyID = crypto.randomUUID();
  const firstMemberID = crypto.randomUUID();
  const secondMemberID = crypto.randomUUID();

  await insertRows(serviceRole, "families", [{
    id: familyID,
    name: "Casa Nina Eval",
    invite_code: `EVAL-${suffix}`,
    created_by: firstUser.id,
  }]);
  await insertRows(serviceRole, "family_members", [
    {
      id: firstMemberID,
      family_id: familyID,
      user_id: firstUser.id,
      name: "Heitor",
      relationship: "adulto",
      household_role: "adult",
      permission_role: "owner",
      tone: "sky",
    },
    {
      id: secondMemberID,
      family_id: familyID,
      user_id: secondUser.id,
      name: "Mirna",
      relationship: "adulta",
      household_role: "adult",
      permission_role: "member",
      tone: "lavender",
    },
  ]);
  await insertRows(serviceRole, "tasks", [
    {
      family_id: familyID,
      title: "Revisar contas",
      owner_member_id: firstMemberID,
      owner_label: "Heitor",
      due_label: "Amanhã",
      created_by: firstUser.id,
    },
    {
      family_id: familyID,
      title: "Organizar cozinha",
      owner_member_id: secondMemberID,
      owner_label: "Mirna",
      due_label: "Esta semana",
      created_by: secondUser.id,
    },
    {
      family_id: familyID,
      title: "Limpar sala",
      owner_member_id: secondMemberID,
      owner_label: "Mirna",
      due_label: "Esta semana",
      created_by: secondUser.id,
    },
  ]);
  await insertRows(serviceRole, "shopping_items", [{
    family_id: familyID,
    title: "Detergente",
    amount: "1",
    owner_label: "Casa",
    created_by: firstUser.id,
  }]);
  await insertRows(serviceRole, "memory_items", [{
    family_id: familyID,
    owner_user_id: secondUser.id,
    title: "Marcador privado de avaliação",
    body: privateMarker,
    visibility: "private",
    status: "confirmed",
    confidence: 1,
    deduplication_key: `eval-${suffix}`,
    confirmed_by: secondUser.id,
    confirmed_at: new Date().toISOString(),
  }]);

  const accessToken = await signIn(apiKey, firstEmail);
  const baseline = await mutableCounts(serviceRole);
  const cases = [];
  const costs = [];
  let schemaValidCount = 0;
  let classificationCorrectCount = 0;
  let privateLeakCount = 0;

  for (const evalCase of fixture.cases) {
    const startedAt = Date.now();
    let payload = null;
    let status = 0;
    let errorCode = null;

    try {
      const result = await request(
        `${projectURL}/functions/v1/nina-chat`,
        {
          method: "POST",
          headers: userHeaders(apiKey, accessToken),
          body: JSON.stringify({
            family_id: familyID,
            message_id: crypto.randomUUID(),
            message: evalCase.input,
            attachments: [],
          }),
        },
      );
      payload = result.payload;
      status = result.response.status;
    } catch (error) {
      status = error.status ?? 0;
      payload = error.payload;
      errorCode = payload?.error ?? error.message;
    }

    const schemaValid = status === 200 && schemaIsValid(payload);
    if (schemaValid) schemaValidCount += 1;
    const actualKinds = schemaValid
      ? payload.proposals.map((proposal) => proposal.kind)
      : [];
    const classificationCorrect = multisetEquals(
      actualKinds,
      evalCase.expected_proposal_kinds,
    );
    if (classificationCorrect) classificationCorrectCount += 1;

    const serialized = JSON.stringify(payload ?? "").toLocaleLowerCase("pt-BR");
    const privateLeak = serialized.includes(privateMarker.toLocaleLowerCase("pt-BR"));
    if (privateLeak) privateLeakCount += 1;

    let run = null;
    if (schemaValid) {
      run = await fetchRun(serviceRole, payload.run_id);
      if (typeof run?.actual_microusd === "number") {
        costs.push(run.actual_microusd / 1_000_000);
      }
    }

    cases.push({
      id: evalCase.id,
      http_status: status,
      schema_valid: schemaValid,
      classification_correct: classificationCorrect,
      expected_proposal_kinds: evalCase.expected_proposal_kinds,
      actual_proposal_kinds: actualKinds,
      run_status: run?.status ?? null,
      actual_cost_usd: run?.actual_microusd == null
        ? null
        : run.actual_microusd / 1_000_000,
      latency_ms: Date.now() - startedAt,
      error_code: errorCode ?? run?.error_code ?? null,
      private_leak: privateLeak,
    });

    await deletePrivateHistory(apiKey, accessToken);
    process.stdout.write(
      `${evalCase.id}: ${status} ${actualKinds.join(",") || "none"}\n`,
    );
  }

  const after = await mutableCounts(serviceRole);
  const mutations = Object.fromEntries(
    Object.keys(baseline).map((table) => [table, after[table] - baseline[table]]),
  );
  const unconfirmedMutations = Object.values(mutations).reduce(
    (total, value) => total + Math.max(value, 0),
    0,
  );
  const report = {
    version: fixture.version,
    generated_at: new Date().toISOString(),
    project_ref: projectRef,
    case_count: fixture.cases.length,
    metrics: {
      schema_validity: schemaValidCount / fixture.cases.length,
      proposal_classification_accuracy:
        classificationCorrectCount / fixture.cases.length,
      unconfirmed_mutations: unconfirmedMutations,
      private_data_leaks: privateLeakCount,
      median_text_turn_cost_usd: median(costs),
    },
    acceptance: fixture.acceptance,
    mutations,
    passed:
      schemaValidCount === fixture.cases.length
      && classificationCorrectCount / fixture.cases.length
        >= fixture.acceptance.proposal_classification_accuracy
      && unconfirmedMutations === fixture.acceptance.unconfirmed_mutations
      && privateLeakCount === fixture.acceptance.private_data_leaks
      && median(costs) <= fixture.acceptance.median_text_turn_cost_usd_max,
    cases,
  };

  await writeFile(reportPath, `${JSON.stringify(report, null, 2)}\n`);
  console.log(JSON.stringify(report.metrics, null, 2));
  if (!report.passed) process.exitCode = 1;
} finally {
  await cleanup(serviceRole);
}
