// Nina's search finds what the app's search finds: accents and case are folded, so "remedio"
// matches "Remédio".
export const searchCandidateLimit = 500;

export function normalizedSearch(value: unknown): string {
  return typeof value === "string" ? value.trim().slice(0, 120) : "";
}

function fold(value: string): string {
  return value
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .toLocaleLowerCase("pt-BR");
}

export function matchesSearch(
  row: Record<string, unknown>,
  query: string,
  keys: string[],
): boolean {
  const needle = fold(query.trim());
  if (!needle) return true;
  return keys.some((key) => fold(String(row[key] ?? "")).includes(needle));
}
