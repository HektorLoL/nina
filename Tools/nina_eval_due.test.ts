import { assertEquals, assertThrows } from "@std/assert";
import {
  dueAtExpectationMet,
  dueAtOnExpectedLocalTime,
  expectedDueInstant,
} from "./nina_eval_due.mjs";

const saturdayMorning = new Date("2026-09-26T10:15:00-03:00");

function expected(
  expectation: Record<string, unknown>,
  now: string | Date,
): string {
  return expectedDueInstant(expectation, new Date(now)).toISOString();
}

function reminder(dueAt: string | null) {
  return { kind: "reminder", payload: { due_at: dueAt } };
}

Deno.test("the eval expects dia 20 on the next twentieth still ahead in São Paulo", () => {
  const dayTwenty = { day_of_month: 20, time: "09:00" };

  assertEquals(
    expected(dayTwenty, saturdayMorning),
    new Date("2026-10-20T09:00:00-03:00").toISOString(),
  );
  assertEquals(
    expected(dayTwenty, "2026-09-20T08:00:00-03:00"),
    new Date("2026-09-20T09:00:00-03:00").toISOString(),
  );
  assertEquals(
    expected(dayTwenty, "2026-09-20T10:00:00-03:00"),
    new Date("2026-10-20T09:00:00-03:00").toISOString(),
  );
});

Deno.test("the eval expects dia 20 do mês que vem in exactly the next month, across the turn of the year", () => {
  const nextMonthsTwentieth = {
    day_of_month: 20,
    months_ahead: 1,
    time: "09:00",
  };

  assertEquals(
    expected(nextMonthsTwentieth, "2026-09-10T10:15:00-03:00"),
    new Date("2026-10-20T09:00:00-03:00").toISOString(),
  );
  assertEquals(
    expected(nextMonthsTwentieth, saturdayMorning),
    new Date("2026-10-20T09:00:00-03:00").toISOString(),
  );
  assertEquals(
    expected(nextMonthsTwentieth, "2026-12-26T10:15:00-03:00"),
    new Date("2027-01-20T09:00:00-03:00").toISOString(),
  );
  assertThrows(() =>
    expected(
      { day_of_month: 31, months_ahead: 1, time: "09:00" },
      "2026-10-10T10:15:00-03:00",
    )
  );
});

Deno.test("the eval expects sexta às 14h on the next Friday, today only before 14:00", () => {
  const fridayAtTwo = { weekday: "sexta", time: "14:00" };

  assertEquals(
    expected(fridayAtTwo, saturdayMorning),
    new Date("2026-10-02T14:00:00-03:00").toISOString(),
  );
  assertEquals(
    expected(fridayAtTwo, "2026-10-02T13:00:00-03:00"),
    new Date("2026-10-02T14:00:00-03:00").toISOString(),
  );
  assertEquals(
    expected(fridayAtTwo, "2026-10-02T15:00:00-03:00"),
    new Date("2026-10-09T14:00:00-03:00").toISOString(),
  );
});

Deno.test("the eval expects amanhã às 9h on the next day whatever the hour", () => {
  const tomorrowAtNine = { days_from_today: 1, time: "09:00" };

  assertEquals(
    expected(tomorrowAtNine, saturdayMorning),
    new Date("2026-09-27T09:00:00-03:00").toISOString(),
  );
  assertEquals(
    expected(tomorrowAtNine, "2026-12-31T23:30:00-03:00"),
    new Date("2027-01-01T09:00:00-03:00").toISOString(),
  );
});

Deno.test("a proposal on another day, at another hour or without a date fails the named-day check", () => {
  const dayTwenty = {
    id: "reminder-day-of-month",
    expected_due_local: { day_of_month: 20, time: "09:00" },
  };

  assertEquals(
    dueAtOnExpectedLocalTime(
      dayTwenty,
      [reminder("2026-10-20T12:00:00Z")],
      saturdayMorning,
    ),
    true,
  );
  assertEquals(
    dueAtOnExpectedLocalTime(dayTwenty, [reminder(null)], saturdayMorning),
    false,
  );
  assertEquals(
    dueAtOnExpectedLocalTime(
      dayTwenty,
      [reminder("2026-10-20T14:00:00-03:00")],
      saturdayMorning,
    ),
    false,
  );
  assertEquals(
    dueAtOnExpectedLocalTime(
      dayTwenty,
      [reminder("2026-10-21T09:00:00-03:00")],
      saturdayMorning,
    ),
    false,
  );
  assertEquals(
    dueAtOnExpectedLocalTime(
      dayTwenty,
      [{ kind: "seed", payload: { due_at: null } }],
      saturdayMorning,
    ),
    false,
  );
  assertEquals(
    dueAtOnExpectedLocalTime(
      { id: "no-action" },
      [reminder(null)],
      saturdayMorning,
    ),
    null,
  );
});

Deno.test("a due_at without a zone fails every date check, whatever the operator's clock", () => {
  const dayTwenty = {
    id: "reminder-day-of-month",
    must_include_due_at: true,
    expected_due_local: { day_of_month: 20, time: "09:00" },
  };
  const zoneless = [reminder("2026-10-20T09:00:00")];

  assertEquals(
    dueAtOnExpectedLocalTime(dayTwenty, zoneless, saturdayMorning),
    false,
  );
  assertEquals(dueAtExpectationMet(dayTwenty, true, zoneless), false);
  assertEquals(
    dueAtExpectationMet(dayTwenty, true, [
      reminder("2026-10-20T09:00:00-03:00"),
    ]),
    true,
  );
});

Deno.test("an expected null due_at fails when Nina dates a period or a part of the day", () => {
  const weekend = { id: "task-no-owner", expected_due_at: null };

  assertEquals(
    dueAtExpectationMet(weekend, true, [
      { kind: "task", payload: { due_at: "2026-09-27T09:00:00-03:00" } },
    ]),
    false,
  );
  assertEquals(
    dueAtExpectationMet(weekend, true, [
      { kind: "task", payload: { due_at: null } },
    ]),
    true,
  );
  assertEquals(dueAtExpectationMet({ id: "no-action" }, true, []), null);
});
