export interface HouseholdMemberRow {
  name?: string | null;
  relationship?: string | null;
  household_role?: string | null;
  memory_note?: string | null;
}

// A child's memory note never crosses the border: it is free text an adult
// wrote about a minor who never consented, and no household task needs it.
export function minimizeMembersForModel(
  rows: readonly HouseholdMemberRow[],
): HouseholdMemberRow[] {
  return rows.map((row) => {
    if (row.household_role !== "child") return { ...row };
    const { memory_note: _withheld, ...retained } = row;
    return retained;
  });
}
