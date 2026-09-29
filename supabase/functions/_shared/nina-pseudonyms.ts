export type AliasKind = "none" | "child" | "teen" | "person" | "adult";

export type RosterEntry = {
  member_id: string;
  name: string;
  names?: string[];
  household_role: string;
  alias_kind: AliasKind;
  nicknames: string[];
  created_at?: string | null;
};

export type ModelMemberRow = {
  id?: string | null;
  name?: string | null;
  relationship?: string | null;
  household_role?: string | null;
  memory_note?: string | null;
};

export const familyAlias = "Casa";

const aliasLabels = {
  child: "Criança",
  teen: "Adolescente",
  person: "Pessoa",
  adult: "Adulto",
} as const;

const minimumFirstTokenLength = 3;
const minimumNicknameLength = 2;
const aliasKinds = new Set<AliasKind>([
  "none",
  "child",
  "teen",
  "person",
  "adult",
]);
const wordCharacter = /[\p{L}\p{N}]/u;

type Term = {
  folded: string;
  replacement: string;
  priority: number;
  shared: boolean;
};

type Match = {
  start: number;
  end: number;
  replacement: string;
  priority: number;
  shared: boolean;
};

export function isRosterEntry(value: unknown): value is RosterEntry {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return false;
  }
  const entry = value as Record<string, unknown>;
  return typeof entry.member_id === "string" &&
    typeof entry.name === "string" &&
    typeof entry.household_role === "string" &&
    typeof entry.alias_kind === "string" &&
    aliasKinds.has(entry.alias_kind as AliasKind) &&
    Array.isArray(entry.nicknames) &&
    entry.nicknames.every((nickname) => typeof nickname === "string") &&
    (entry.names === undefined ||
      (Array.isArray(entry.names) &&
        entry.names.every((name) => typeof name === "string")));
}

function foldCharacter(character: string): string {
  return character.normalize("NFD").replace(/\p{M}/gu, "").toLocaleLowerCase(
    "pt-BR",
  );
}

export function foldText(value: string): string {
  let folded = "";
  for (const character of value) folded += foldCharacter(character);
  return folded.replace(/\s+/g, " ").trim();
}

function foldWithOffsets(
  value: string,
): { folded: string; starts: number[]; ends: number[] } {
  let folded = "";
  const starts: number[] = [];
  const ends: number[] = [];
  let offset = 0;
  for (const character of value) {
    const replacement = foldCharacter(character);
    for (let unit = 0; unit < replacement.length; unit += 1) {
      starts.push(offset);
      ends.push(offset + character.length);
    }
    folded += replacement;
    offset += character.length;
  }
  return { folded, starts, ends };
}

function isBoundary(folded: string, index: number): boolean {
  if (index < 0 || index >= folded.length) return true;
  return !wordCharacter.test(folded[index]);
}

function firstToken(name: string): string {
  return foldText(name).split(" ")[0] ?? "";
}

function knownNames(entry: RosterEntry): string[] {
  const seen = new Set<string>();
  const result: string[] = [];
  for (const name of [entry.name, ...(entry.names ?? [])]) {
    const trimmed = name.trim();
    const folded = foldText(trimmed);
    if (!folded || seen.has(folded)) continue;
    seen.add(folded);
    result.push(trimmed);
  }
  return result;
}

function containsTerm(folded: string, term: string): boolean {
  let from = 0;
  while (from <= folded.length - term.length) {
    const index = folded.indexOf(term, from);
    if (index === -1) return false;
    if (
      isBoundary(folded, index - 1) && isBoundary(folded, index + term.length)
    ) {
      return true;
    }
    from = index + 1;
  }
  return false;
}

function byRosterOrder(left: RosterEntry, right: RosterEntry): number {
  const leftCreated = left.created_at ?? "";
  const rightCreated = right.created_at ?? "";
  if (leftCreated !== rightCreated) {
    return leftCreated < rightCreated ? -1 : 1;
  }
  return left.member_id < right.member_id
    ? -1
    : left.member_id > right.member_id
    ? 1
    : 0;
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

export class Pseudonymizer {
  readonly aliasByMember = new Map<string, string>();
  readonly kindByMember = new Map<string, AliasKind>();
  readonly excludedOwnerIDs = new Set<string>();
  private readonly terms: Term[] = [];
  private readonly restorations: Array<
    { pattern: RegExp; alias: string; name: string; memberID: string }
  > = [];
  private readonly consentingAdultIDs = new Set<string>();
  private readonly displayNameByMember = new Map<string, string>();
  private readonly sharedSurfaceByAlias = new Map<string, string>();
  private readonly namedAliases = new Set<string>();

  constructor(roster: readonly RosterEntry[], familyName?: string | null) {
    const ordered = [...roster].sort(byRosterOrder);
    const counters = { child: 0, teen: 0, person: 0, adult: 0 };
    const isMinor = (entry: RosterEntry) =>
      entry.alias_kind === "child" || entry.alias_kind === "teen" ||
      entry.alias_kind === "person";

    const minorTerms = new Set<string>();
    for (const entry of ordered) {
      if (!isMinor(entry)) continue;
      for (const name of knownNames(entry)) {
        minorTerms.add(foldText(name));
        const token = firstToken(name);
        if (token.length >= minimumFirstTokenLength) minorTerms.add(token);
      }
      for (const nickname of entry.nicknames) {
        const folded = foldText(nickname);
        if (folded.length >= minimumNicknameLength) minorTerms.add(folded);
      }
    }

    // An adult whose name holds a minor's name, first name or nickname is
    // given a code of their own, so a structured field can name that adult
    // without the shared word, which in free text always reads as the minor.
    const collides = (entry: RosterEntry) =>
      entry.household_role === "adult" && !isMinor(entry) &&
      knownNames(entry).some((name) => {
        const folded = foldText(name);
        return [...minorTerms].some((term) => containsTerm(folded, term));
      });

    const aliasKindOf = (entry: RosterEntry): AliasKind =>
      entry.alias_kind === "none" && collides(entry)
        ? "adult"
        : entry.alias_kind;

    const unaliasedTokens = new Set<string>();
    const adultTokens = new Set<string>();
    for (const entry of ordered) {
      this.displayNameByMember.set(entry.member_id, entry.name.trim());
      for (const name of knownNames(entry)) {
        const folded = foldText(name);
        const token = firstToken(name);
        if (entry.household_role === "adult" && !isMinor(entry)) {
          adultTokens.add(folded);
          if (token) adultTokens.add(token);
        }
        if (aliasKindOf(entry) !== "none") continue;
        unaliasedTokens.add(folded);
        if (token) unaliasedTokens.add(token);
      }
    }

    for (const entry of ordered) {
      const kind = aliasKindOf(entry);
      if (kind === "none") continue;
      if (entry.alias_kind === "none") {
        this.consentingAdultIDs.add(entry.member_id);
      }
      counters[kind] += 1;
      const alias = `${aliasLabels[kind]} ${counters[kind]}`;
      this.aliasByMember.set(entry.member_id, alias);
      this.kindByMember.set(entry.member_id, kind);

      const minor = kind !== "adult";
      if (minor) this.excludedOwnerIDs.add(entry.member_id);
      const colliding = !minor && collides(entry);

      for (const name of knownNames(entry)) {
        const fullName = foldText(name);
        if (!fullName) continue;
        if (colliding) {
          if (!minorTerms.has(fullName) && fullName !== firstToken(name)) {
            this.terms.push({
              folded: fullName,
              replacement: alias,
              priority: 0,
              shared: false,
            });
          }
          continue;
        }

        this.terms.push({
          folded: fullName,
          replacement: alias,
          priority: minor ? 0 : 1,
          shared: false,
        });

        // A child or teen sharing a first name with anyone else is still
        // aliased everywhere: the collision is resolved toward the minor.
        const token = firstToken(name);
        if (
          token.length >= minimumFirstTokenLength &&
          token !== fullName &&
          (minor || !unaliasedTokens.has(token))
        ) {
          this.terms.push({
            folded: token,
            replacement: alias,
            priority: minor ? 0 : 1,
            shared: minor && adultTokens.has(token),
          });
        }
      }

      if (minor) {
        for (const nickname of entry.nicknames) {
          const folded = foldText(nickname);
          if (folded.length >= minimumNicknameLength) {
            this.terms.push({
              folded,
              replacement: alias,
              priority: 0,
              shared: adultTokens.has(folded),
            });
          }
        }
      }

      this.restorations.push({
        pattern: new RegExp(
          `(?<![\\p{L}\\p{N}])${escapeRegExp(alias)}(?![\\p{L}\\p{N}])`,
          "giu",
        ),
        alias,
        name: entry.name.trim(),
        memberID: entry.member_id,
      });
    }

    const household = foldText(familyName ?? "");
    if (household && household !== foldText(familyAlias)) {
      this.terms.push({
        folded: household,
        replacement: familyAlias,
        priority: 2,
        shared: false,
      });
    }

    this.restorations.sort((left, right) =>
      right.pattern.source.length - left.pattern.source.length
    );
  }

  text(value: string): string {
    if (!value || this.terms.length === 0) return value;
    const { folded, starts, ends } = foldWithOffsets(value);
    const candidates: Match[] = [];

    for (const term of this.terms) {
      let from = 0;
      while (from <= folded.length - term.folded.length) {
        const index = folded.indexOf(term.folded, from);
        if (index === -1) break;
        const end = index + term.folded.length;
        if (isBoundary(folded, index - 1) && isBoundary(folded, end)) {
          candidates.push({
            start: index,
            end,
            replacement: term.replacement,
            priority: term.priority,
            shared: term.shared,
          });
        }
        from = index + 1;
      }
    }

    if (candidates.length === 0) return value;

    candidates.sort((left, right) =>
      left.priority - right.priority ||
      (right.end - right.start) - (left.end - left.start) ||
      left.start - right.start
    );
    const accepted: Match[] = [];
    for (const candidate of candidates) {
      if (
        accepted.every((match) =>
          candidate.end <= match.start || candidate.start >= match.end
        )
      ) {
        accepted.push(candidate);
      }
    }

    accepted.sort((left, right) => right.start - left.start);
    let result = value;
    for (const match of accepted) {
      const originalStart = starts[match.start];
      const originalEnd = ends[match.end - 1];
      if (match.shared) {
        if (!this.sharedSurfaceByAlias.has(match.replacement)) {
          this.sharedSurfaceByAlias.set(
            match.replacement,
            value.slice(originalStart, originalEnd),
          );
        }
      } else {
        this.namedAliases.add(match.replacement);
      }
      result = result.slice(0, originalStart) + match.replacement +
        result.slice(originalEnd);
    }
    return result;
  }

  // A minor's code that entered the request only through a first name an
  // adult also carries was never known to mean the minor, so it goes back as
  // the word the person wrote, and it never assigns work to anyone.
  private ambiguousSurface(alias: string): string | null {
    if (this.namedAliases.has(alias)) return null;
    return this.sharedSurfaceByAlias.get(alias) ?? null;
  }

  structuredName(memberID: string, fallback: string): string {
    return this.aliasByMember.get(memberID) ?? fallback;
  }

  structuredLabel(label: string): string {
    const trimmed = label.trim();
    for (const [memberID, alias] of this.aliasByMember) {
      const name = this.displayNameByMember.get(memberID);
      if (!name) continue;
      if (trimmed === name) return alias;
      if (trimmed.startsWith(`${name} · `)) {
        return `${alias}${trimmed.slice(name.length)}`;
      }
    }
    return label;
  }

  structuredKeys<T>(value: Record<string, T>): Record<string, T> {
    const result: Record<string, T> = {};
    for (const [key, item] of Object.entries(value)) {
      result[this.structuredLabel(key)] = item;
    }
    return result;
  }

  deep<T>(value: T): T {
    return this.transform(value, (text) => this.text(text)) as T;
  }

  restoreText(value: string): string {
    let result = value;
    for (const restoration of this.restorations) {
      result = result.replace(
        restoration.pattern,
        this.ambiguousSurface(restoration.alias) ?? restoration.name,
      );
    }
    return result;
  }

  restoreDeep<T>(value: T): T {
    return this.transform(value, (text) => this.restoreText(text)) as T;
  }

  restoreProposals<T>(proposals: readonly T[]): T[] {
    return proposals.map((proposal) => {
      const restored = this.restoreDeep(proposal);
      const payload = (proposal as { payload?: { owner?: unknown } }).payload;
      const owner = typeof payload?.owner === "string"
        ? payload.owner.trim()
        : "";
      const alias = [...this.sharedSurfaceByAlias.keys()].find((candidate) =>
        candidate.toLocaleLowerCase("pt-BR") ===
          owner.toLocaleLowerCase("pt-BR")
      );
      if (alias && this.ambiguousSurface(alias) !== null) {
        const restoredPayload =
          (restored as { payload?: Record<string, unknown> }).payload;
        if (restoredPayload) restoredPayload.owner = familyAlias;
      }
      return restored;
    });
  }

  memberIDForAlias(value: string): string | null {
    const trimmed = value.trim();
    for (const restoration of this.restorations) {
      restoration.pattern.lastIndex = 0;
      const exact = new RegExp(`^${restoration.pattern.source}$`, "iu");
      if (exact.test(trimmed)) return restoration.memberID;
    }
    return null;
  }

  // Relationship, memory note and birth date describe a person the model may
  // not name, so an aliased member reaches the model as the alias alone.
  memberContext(
    rows: readonly ModelMemberRow[],
  ): Array<Record<string, unknown>> {
    return rows.map((row) => {
      const id = typeof row.id === "string" ? row.id : "";
      const alias = this.aliasByMember.get(id);
      if (alias && this.consentingAdultIDs.has(id)) {
        return {
          ...this.deep({
            relationship: row.relationship ?? "",
            memory_note: row.memory_note ?? "",
          }),
          name: alias,
          household_role: "adult",
        };
      }
      if (alias) {
        return {
          name: alias,
          household_role: this.kindByMember.get(id) ?? "person",
        };
      }
      const retained: Record<string, unknown> = {
        name: row.name ?? "",
        relationship: row.relationship ?? "",
        household_role: row.household_role ?? "",
      };
      if (row.household_role !== "child" && row.household_role !== "teen") {
        retained.memory_note = row.memory_note ?? "";
      }
      return this.deep(retained);
    });
  }

  withoutMinorWork<T extends { owner_member_id?: string | null }>(
    rows: readonly T[],
  ): T[] {
    return rows.filter((row) =>
      !row.owner_member_id || !this.excludedOwnerIDs.has(row.owner_member_id)
    );
  }

  private transform(value: unknown, map: (text: string) => string): unknown {
    if (typeof value === "string") return map(value);
    if (Array.isArray(value)) {
      return value.map((item) => this.transform(item, map));
    }
    if (value && typeof value === "object") {
      const result: Record<string, unknown> = {};
      for (const [key, item] of Object.entries(value)) {
        result[map(key)] = this.transform(item, map);
      }
      return result;
    }
    return value;
  }
}
