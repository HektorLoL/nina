export const houseWorkloadKey = "Casa";

export type WorkloadTaskRow = {
  owner_member_id?: string | null;
  owner_label?: string | null;
  is_done?: boolean | null;
  priority?: string | null;
};

export type WorkloadMemberRow = {
  id?: string | null;
  name?: string | null;
  relationship?: string | null;
  household_role?: string | null;
};

export type WorkloadBucket = {
  open: number;
  completed: number;
  urgent: number;
};

function trimmedField(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function folded(value: string): string {
  return value.trim().toLocaleLowerCase("pt-BR");
}

export function workloadDisplayNames(
  members: readonly WorkloadMemberRow[],
): Map<string, string> {
  const people = members.flatMap((member) => {
    const id = trimmedField(member.id);
    const name = trimmedField(member.name);
    if (!id || !name || member.household_role === "assistant") return [];
    return [{ id, name, relationship: trimmedField(member.relationship) }];
  });

  const seen = new Set<string>();
  const shared = new Set<string>();
  for (const person of people) {
    const nameKey = folded(person.name);
    if (seen.has(nameKey)) shared.add(nameKey);
    seen.add(nameKey);
  }

  // Casa is the house bucket and never a person, so a member carrying that
  // name is qualified away from it instead of absorbing the household's work.
  const taken = new Set<string>([folded(houseWorkloadKey)]);
  const ordinals = new Map<string, number>();
  const displayNames = new Map<string, string>();

  for (const person of people) {
    const nameKey = folded(person.name);
    const ordinal = (ordinals.get(nameKey) ?? 0) + 1;
    ordinals.set(nameKey, ordinal);

    const qualifier = person.relationship || String(ordinal);
    let displayName = shared.has(nameKey) || taken.has(nameKey)
      ? `${person.name} · ${qualifier}`
      : person.name;
    let repeat = 1;
    while (taken.has(folded(displayName))) {
      repeat += 1;
      displayName = `${person.name} · ${qualifier} ${repeat}`;
    }

    taken.add(folded(displayName));
    displayNames.set(person.id, displayName);
  }

  return displayNames;
}

export function summarizeWorkload(
  tasks: readonly WorkloadTaskRow[],
  members: readonly WorkloadMemberRow[],
): Record<string, WorkloadBucket> {
  const displayNames = workloadDisplayNames(members);
  const summary: Record<string, WorkloadBucket> = {};

  for (const task of tasks) {
    const memberID = trimmedField(task.owner_member_id);
    const resolved = memberID ? displayNames.get(memberID) : undefined;
    // Work whose owner no longer resolves keeps its own label rather than
    // being credited to a person who may not be the one who was meant.
    const owner = resolved
      || trimmedField(task.owner_label)
      || houseWorkloadKey;

    summary[owner] ??= { open: 0, completed: 0, urgent: 0 };
    const bucket = summary[owner];

    if (task.is_done) {
      bucket.completed += 1;
      continue;
    }

    bucket.open += 1;
    if (task.priority === "urgent") bucket.urgent += 1;
  }

  return summary;
}
