export interface HouseholdMemberRow {
  name?: string | null;
  relationship?: string | null;
  household_role?: string | null;
  memory_note?: string | null;
}

// A child's or teen's memory note never crosses the border: it is free text
// an adult wrote about a minor who never consented, and no task needs it.
export function minimizeMembersForModel<T extends HouseholdMemberRow>(
  rows: readonly T[],
): T[] {
  return rows.map((row) => {
    if (row.household_role !== "child" && row.household_role !== "teen") {
      return { ...row };
    }
    const { memory_note: _withheld, ...retained } = row;
    return retained as T;
  });
}
