export interface HouseholdMemberRow {
  name?: string | null;
  relationship?: string | null;
  household_role?: string | null;
  memory_note?: string | null;
  pet_species?: string | null;
  pet_breed?: string | null;
}

// A child's or teen's memory note never crosses the border: it is free text
// an adult wrote about a minor who never consented, and no task needs it.
export function minimizeMembersForModel<T extends HouseholdMemberRow>(
  rows: readonly T[],
): T[] {
  return rows.map((row) => {
    const retained: Partial<HouseholdMemberRow> = { ...row };
    // Species and breed describe an animal; on anyone else they are empty columns and stay home.
    if (row.household_role !== "pet") {
      delete retained.pet_species;
      delete retained.pet_breed;
    }
    if (row.household_role === "child" || row.household_role === "teen") {
      delete retained.memory_note;
    }
    return retained as unknown as T;
  });
}
