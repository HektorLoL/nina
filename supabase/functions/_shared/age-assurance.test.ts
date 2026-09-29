import { assert, assertEquals, assertFalse } from "@std/assert";
import {
  type AgeSignal,
  mapAgeRange,
  type MappedAge,
  maxSignalJSONBytes,
  parseAgeSignalJSON,
  signalKeys,
} from "./age-assurance.ts";

function sharing(
  lower: number | null,
  upper: number | null,
  declaration: AgeSignal["declaration"],
  parentalControls: string[] = [],
): AgeSignal {
  return {
    declaration,
    eligible_for_age_features: null,
    lower_bound: lower,
    outcome: "sharing",
    parental_controls: parentalControls,
    regulatory_features: [],
    upper_bound: upper,
  };
}

const declined: AgeSignal = {
  declaration: null,
  eligible_for_age_features: null,
  lower_bound: null,
  outcome: "declined",
  parental_controls: [],
  regulatory_features: [],
  upper_bound: null,
};

// The same table is asserted by Nina/AgeAssurance.swift, so the device and the
// server can never disagree about what a range means.
const table: Array<[string, AgeSignal, MappedAge]> = [
  ["a", declined, {
    status: "unknown",
    band: null,
    assurance: "none",
    parentalControlsActive: false,
  }],
  ["b", sharing(18, null, "confirmed"), {
    status: "adult",
    band: null,
    assurance: "confirmed",
    parentalControlsActive: false,
  }],
  ["c", sharing(18, null, "self_declared"), {
    status: "adult",
    band: null,
    assurance: "self_declared",
    parentalControlsActive: false,
  }],
  ["d", sharing(18, null, "payment_checked"), {
    status: "adult",
    band: null,
    assurance: "confirmed",
    parentalControlsActive: false,
  }],
  ["e", sharing(18, null, "confirmed", ["communication_limits"]), {
    status: "adult",
    band: null,
    assurance: "confirmed",
    parentalControlsActive: true,
  }],
  ["f", sharing(16, 17, "guardian_declared"), {
    status: "minor",
    band: "16_17",
    assurance: "guardian_declared",
    parentalControlsActive: false,
  }],
  ["g", sharing(null, 12, null), {
    status: "minor",
    band: "under_12",
    assurance: "none",
    parentalControlsActive: false,
  }],
  ["h", sharing(13, 15, "self_declared"), {
    status: "minor",
    band: "12_15",
    assurance: "self_declared",
    parentalControlsActive: false,
  }],
  ["i", sharing(16, 20, "self_declared"), {
    status: "minor",
    band: "16_17",
    assurance: "self_declared",
    parentalControlsActive: false,
  }],
  ["j", sharing(12, 15, "guardian_checked_by_other_method"), {
    status: "minor",
    band: "12_15",
    assurance: "guardian_declared",
    parentalControlsActive: false,
  }],
];

Deno.test("the age range table maps every row the device mirror asserts", () => {
  for (const [row, signal, expected] of table) {
    assertEquals(mapAgeRange(signal), expected, `row ${row}`);
  }
});

Deno.test("a declined share records unknown", () => {
  assertEquals(mapAgeRange(declined).status, "unknown");
  assertEquals(mapAgeRange(declined).assurance, "none");
});

Deno.test("a range that straddles eighteen records the youngest band", () => {
  const mapped = mapAgeRange(sharing(16, 20, "confirmed"));
  assertEquals(mapped.status, "minor");
  assertEquals(mapped.band, "16_17");
});

Deno.test("active parental controls never yield a trusted adult", () => {
  const mapped = mapAgeRange(
    sharing(18, null, "confirmed", [
      "significant_app_change_approval_required",
    ]),
  );
  assertEquals(mapped.status, "adult");
  assert(mapped.parentalControlsActive);
});

Deno.test("a deprecated checked declaration counts as confirmed", () => {
  for (
    const declaration of [
      "checked_by_other_method",
      "payment_checked",
      "government_id_checked",
    ] as const
  ) {
    assertEquals(
      mapAgeRange(sharing(18, null, declaration)).assurance,
      "confirmed",
      declaration,
    );
  }
});

Deno.test("a self-declared adult is never trusted", () => {
  assertEquals(
    mapAgeRange(sharing(18, null, "self_declared")).assurance,
    "self_declared",
  );
  assertEquals(mapAgeRange(sharing(18, null, null)).assurance, "self_declared");
  assertEquals(
    mapAgeRange(sharing(18, null, "guardian_declared")).assurance,
    "self_declared",
  );
});

Deno.test("eligibility for age features never changes the answer", () => {
  for (const eligible of [true, false, null]) {
    assertEquals(
      mapAgeRange({
        ...sharing(13, 15, "self_declared"),
        eligible_for_age_features: eligible,
      }),
      mapAgeRange(sharing(13, 15, "self_declared")),
    );
  }
});

Deno.test("the signed signal is parsed only with exactly its seven keys", () => {
  const canonical = JSON.stringify(
    Object.fromEntries(
      signalKeys.map((key) => [key, (sharing(18, null, "confirmed"))[key]]),
    ),
  );
  assertEquals(parseAgeSignalJSON(canonical), sharing(18, null, "confirmed"));
  assertEquals(
    parseAgeSignalJSON(JSON.stringify(declined)),
    declined,
  );

  const extra = JSON.stringify({
    ...sharing(18, null, "confirmed"),
    birth_date: "2000-01-01",
  });
  const missing = JSON.stringify({
    ...sharing(18, null, "confirmed"),
    upper_bound: undefined,
  });
  for (
    const invalid of [
      extra,
      missing,
      "[]",
      "not json",
      JSON.stringify({ ...declined, declaration: "confirmed" }),
      JSON.stringify({ ...declined, lower_bound: 18 }),
      JSON.stringify({ ...sharing(18, null, "confirmed"), outcome: "error" }),
      JSON.stringify({ ...sharing(20, 18, "confirmed") }),
      JSON.stringify({ ...sharing(18.5, null, "confirmed") }),
      JSON.stringify({ ...sharing(18, null, null), declaration: "trusted" }),
      JSON.stringify({ ...sharing(18, null, "confirmed", ["screen_time"]) }),
      JSON.stringify({
        ...sharing(18, null, "confirmed"),
        regulatory_features: ["everything"],
      }),
      JSON.stringify({
        ...sharing(18, null, "confirmed"),
        eligible_for_age_features: "yes",
      }),
    ]
  ) {
    assertEquals(parseAgeSignalJSON(invalid), null, invalid);
  }
  assertFalse(
    parseAgeSignalJSON(" ".repeat(maxSignalJSONBytes) + canonical) !== null,
  );
});
