interface Env {
  ASSETS: Fetcher;
  SUPABASE_URL?: string;
  SUPABASE_PUBLISHABLE_KEY?: string;
  NINA_SUPABASE_URL?: string;
  NINA_SUPABASE_PUBLISHABLE_KEY?: string;
}

interface InvitePreview {
  valid: boolean;
  family_name?: string;
}

const securityHeaders = {
  "Content-Security-Policy":
    "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; connect-src 'self' https://*.supabase.co; base-uri 'self'; form-action 'self'; frame-ancestors 'none'",
  "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
  "Referrer-Policy": "strict-origin-when-cross-origin",
  "X-Content-Type-Options": "nosniff",
};

function jsonResponse(body: unknown, status: number): Response {
  return Response.json(body, {
    status,
    headers: { "Cache-Control": "no-store" },
  });
}

async function getInvitePreview(code: string, env: Env): Promise<Response> {
  const normalizedCode = code.toLowerCase().replace(/[^a-z0-9-]/g, "");

  if (normalizedCode.length < 12 || normalizedCode.length > 96) {
    return jsonResponse({ valid: false, error: "invalid_invite" }, 400);
  }

  const supabaseUrl = env.SUPABASE_URL ?? env.NINA_SUPABASE_URL;
  const publishableKey =
    env.SUPABASE_PUBLISHABLE_KEY ?? env.NINA_SUPABASE_PUBLISHABLE_KEY;

  if (!supabaseUrl || !publishableKey) {
    return jsonResponse({ valid: false, error: "invite_lookup_unavailable" }, 503);
  }

  const response = await fetch(`${supabaseUrl}/rest/v1/rpc/get_family_invite_preview`, {
    method: "POST",
    headers: {
      apikey: publishableKey,
      Authorization: `Bearer ${publishableKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ invite_code: normalizedCode }),
  });

  if (!response.ok) {
    return jsonResponse({ valid: false, error: "invite_lookup_failed" }, 502);
  }

  const preview = (await response.json()) as InvitePreview;
  if (!preview.valid) {
    return jsonResponse({ valid: false, error: "invite_not_found" }, 404);
  }

  return jsonResponse(
    {
      valid: true,
      verified: true,
      familyName: preview.family_name ?? "Uma casa na Nina",
    },
    200,
  );
}

async function serveInvitePage(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  url.pathname = "/join/";

  const response = await env.ASSETS.fetch(new Request(url, request));
  const headers = new Headers(response.headers);

  for (const [name, value] of Object.entries(securityHeaders)) {
    headers.set(name, value);
  }

  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const inviteApiMatch = url.pathname.match(/^\/api\/invite\/([^/]+)\/?$/);

    if (request.method === "GET" && inviteApiMatch) {
      return getInvitePreview(inviteApiMatch[1], env);
    }

    if (request.method === "GET" && url.pathname.startsWith("/invite/")) {
      return serveInvitePage(request, env);
    }

    return env.ASSETS.fetch(request);
  },
} satisfies ExportedHandler<Env>;
