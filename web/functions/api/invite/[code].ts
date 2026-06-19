interface Env {
  SUPABASE_URL?: string;
  SUPABASE_PUBLISHABLE_KEY?: string;
}

interface InvitePreview {
  valid: boolean;
  family_name?: string;
}

export const onRequestGet: PagesFunction<Env> = async ({ params, env }) => {
  const rawCode = typeof params.code === "string" ? params.code : "";
  const code = rawCode.toLowerCase().replace(/[^a-z0-9-]/g, "");

  if (code.length < 12 || code.length > 96) {
    return Response.json({ valid: false, error: "invalid_invite" }, { status: 400 });
  }

  if (!env.SUPABASE_URL || !env.SUPABASE_PUBLISHABLE_KEY) {
    return Response.json(
      { valid: false, error: "invite_lookup_unavailable" },
      { status: 503, headers: { "Cache-Control": "no-store" } },
    );
  }

  const response = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/get_family_invite_preview`, {
    method: "POST",
    headers: {
      apikey: env.SUPABASE_PUBLISHABLE_KEY,
      Authorization: `Bearer ${env.SUPABASE_PUBLISHABLE_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ invite_code: code }),
  });

  if (!response.ok) {
    return Response.json({ valid: false, error: "invite_lookup_failed" }, { status: 502 });
  }

  const preview = (await response.json()) as InvitePreview;
  if (!preview.valid) {
    return Response.json({ valid: false, error: "invite_not_found" }, { status: 404 });
  }

  return Response.json(
    {
      valid: true,
      verified: true,
      familyName: preview.family_name ?? "Uma casa na Nina",
    },
    { headers: { "Cache-Control": "no-store" } },
  );
};
