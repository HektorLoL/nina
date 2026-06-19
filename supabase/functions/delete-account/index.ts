import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2";

type FamilyMember = {
  family_id: string;
  user_id: string | null;
  household_role: string;
  permission_role: string;
  created_at: string;
};

type FamilyRow = {
  id: string;
  created_by: string;
};

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

async function checked<T>(
  result: PromiseLike<{ data: T | null; error: unknown }>,
  code: string,
): Promise<T> {
  const { data, error } = await result;
  if (error) {
    console.error(JSON.stringify({ event: "delete_account_failed", code }));
    throw new Error(code);
  }
  return data as T;
}

function replacementMember(members: FamilyMember[]): FamilyMember | undefined {
  return members.find((member) =>
    member.household_role === "adult" &&
    ["owner", "admin"].includes(member.permission_role)
  ) ?? members.find((member) => member.household_role === "adult") ??
    members[0];
}

async function deleteProfilePhoto(admin: SupabaseClient, userID: string) {
  const bucket = admin.storage.from("profile-photos");
  const { data, error } = await bucket.list(userID, { limit: 1000 });
  if (error) {
    console.error(JSON.stringify({
      event: "delete_account_failed",
      code: "list_profile_photos",
    }));
    throw new Error("list_profile_photos");
  }
  if (!data?.length) return;

  const paths = data.map((file) => `${userID}/${file.name}`);
  const { error: removeError } = await bucket.remove(paths);
  if (removeError) {
    console.error(JSON.stringify({
      event: "delete_account_failed",
      code: "delete_profile_photos",
    }));
    throw new Error("delete_profile_photos");
  }
}

async function deletePrivateContent(admin: SupabaseClient, userID: string) {
  await checked(
    admin.from("nina_proposals").delete().eq("owner_user_id", userID),
    "delete_proposals",
  );
  await checked(
    admin.from("nina_threads").delete().eq("owner_user_id", userID),
    "delete_threads",
  );
  await checked(
    admin.from("memory_items").delete().or(
      `owner_user_id.eq.${userID},created_by.eq.${userID}`,
    ),
    "delete_memories",
  );
  await checked(
    admin.from("chat_messages").delete().eq("created_by", userID),
    "delete_chat_messages",
  );
}

async function preserveSharedFamilies(admin: SupabaseClient, userID: string) {
  const memberships = await checked<FamilyMember[]>(
    admin
      .from("family_members")
      .select("family_id,user_id,household_role,permission_role,created_at")
      .eq("user_id", userID),
    "load_memberships",
  );

  for (const membership of memberships) {
    const members = await checked<FamilyMember[]>(
      admin
        .from("family_members")
        .select("family_id,user_id,household_role,permission_role,created_at")
        .eq("family_id", membership.family_id)
        .order("created_at"),
      "load_family_members",
    );

    const otherClaimedMembers = members.filter((member) =>
      member.user_id && member.user_id !== userID &&
      member.household_role !== "assistant"
    );

    if (otherClaimedMembers.length === 0) {
      await checked(
        admin.from("families").delete().eq("id", membership.family_id),
        "delete_family",
      );
      continue;
    }

    const replacement = replacementMember(otherClaimedMembers);
    if (!replacement?.user_id) {
      throw new Error("missing_replacement_member");
    }

    const family = await checked<FamilyRow | null>(
      admin
        .from("families")
        .select("id,created_by")
        .eq("id", membership.family_id)
        .maybeSingle(),
      "load_family",
    );

    if (family?.created_by === userID) {
      await checked(
        admin
          .from("families")
          .update({ created_by: replacement.user_id })
          .eq("id", membership.family_id),
        "transfer_family_creator",
      );
    }

    const remainingOwnerExists = otherClaimedMembers.some((member) =>
      member.permission_role === "owner"
    );
    if (membership.permission_role === "owner" && !remainingOwnerExists) {
      await checked(
        admin
          .from("family_members")
          .update({ permission_role: "owner" })
          .eq("family_id", membership.family_id)
          .eq("user_id", replacement.user_id),
        "promote_replacement_owner",
      );
    }
  }
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = parseConfiguredKey(
    "SUPABASE_SECRET_KEYS",
    "SUPABASE_SERVICE_ROLE_KEY",
  );
  if (!supabaseURL || !serviceRoleKey) {
    return jsonResponse({ error: "service_not_configured" }, 503);
  }

  const authorization = request.headers.get("Authorization") ?? "";
  const jwt = authorization.replace(/^Bearer\s+/i, "").trim();
  if (!jwt) {
    return jsonResponse({ error: "not_authenticated" }, 401);
  }

  const admin = createClient(supabaseURL, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: authData, error: authError } = await admin.auth.getUser(jwt);
  if (authError || !authData.user) {
    return jsonResponse({ error: "not_authenticated" }, 401);
  }

  const userID = authData.user.id;
  try {
    await deleteProfilePhoto(admin, userID);
    await deletePrivateContent(admin, userID);
    await preserveSharedFamilies(admin, userID);

    const { error: deleteError } = await admin.auth.admin.deleteUser(userID);
    if (deleteError) throw deleteError;

    return jsonResponse({ deleted: true });
  } catch (error) {
    console.error(JSON.stringify({
      event: "delete_account_failed",
      user_id: userID,
      reason: String(error),
    }));
    return jsonResponse({ error: "delete_account_failed" }, 503);
  }
});
