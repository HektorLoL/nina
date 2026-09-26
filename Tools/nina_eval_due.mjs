const evalTimeZone = "America/Sao_Paulo";

const evalWeekdays = {
  domingo: 0,
  segunda: 1,
  terca: 2,
  quarta: 3,
  quinta: 4,
  sexta: 5,
  sabado: 6,
};

const evalWallFormatter = new Intl.DateTimeFormat("en-US", {
  timeZone: evalTimeZone,
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
  second: "2-digit",
  hourCycle: "h23",
});

function wallClock(instant) {
  const parts = Object.fromEntries(
    evalWallFormatter.formatToParts(instant).map((part) => [
      part.type,
      Number(part.value),
    ]),
  );
  return {
    year: parts.year,
    month: parts.month,
    day: parts.day,
    hour: parts.hour,
    minute: parts.minute,
    second: parts.second,
  };
}

function offsetMilliseconds(instant) {
  const wall = wallClock(instant);
  const wallAsUTC = Date.UTC(
    wall.year,
    wall.month - 1,
    wall.day,
    wall.hour,
    wall.minute,
    wall.second,
  );
  return wallAsUTC - Math.floor(instant.getTime() / 1000) * 1000;
}

function localInstant(year, month, day, hour, minute) {
  const wallAsUTC = Date.UTC(year, month - 1, day, hour, minute);
  const firstGuess = wallAsUTC - offsetMilliseconds(new Date(wallAsUTC));
  return new Date(wallAsUTC - offsetMilliseconds(new Date(firstGuess)));
}

function localDayAfter(year, month, day, days) {
  const shifted = new Date(Date.UTC(year, month - 1, day + days));
  return {
    year: shifted.getUTCFullYear(),
    month: shifted.getUTCMonth() + 1,
    day: shifted.getUTCDate(),
  };
}

function weekdayName(text) {
  return text
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .toLowerCase()
    .replace(/-feira$/, "");
}

export function expectedDueInstant(expectation, now) {
  const [hour, minute] = expectation.time.split(":").map(Number);
  const today = wallClock(now);
  const at = (day) => localInstant(day.year, day.month, day.day, hour, minute);
  const isAhead = (instant) => instant.getTime() > now.getTime();

  if (typeof expectation.days_from_today === "number") {
    return at(
      localDayAfter(
        today.year,
        today.month,
        today.day,
        expectation.days_from_today,
      ),
    );
  }

  if (
    typeof expectation.day_of_month === "number" &&
    typeof expectation.months_ahead === "number"
  ) {
    const step = today.month - 1 + expectation.months_ahead;
    const year = today.year + Math.floor(step / 12);
    const month = (step % 12) + 1;
    const monthLength = new Date(Date.UTC(year, month, 0)).getUTCDate();
    if (expectation.day_of_month > monthLength) {
      throw new Error("day_of_month_outside_month");
    }
    return at({ year, month, day: expectation.day_of_month });
  }

  if (typeof expectation.day_of_month === "number") {
    for (let step = 0; step < 13; step += 1) {
      const year = today.year + Math.floor((today.month - 1 + step) / 12);
      const month = ((today.month - 1 + step) % 12) + 1;
      const monthLength = new Date(Date.UTC(year, month, 0)).getUTCDate();
      if (expectation.day_of_month > monthLength) continue;
      const candidate = at({ year, month, day: expectation.day_of_month });
      if (isAhead(candidate)) return candidate;
    }
    throw new Error("unreachable_day_of_month");
  }

  if (typeof expectation.weekday === "string") {
    const target = evalWeekdays[weekdayName(expectation.weekday)];
    if (target === undefined) throw new Error("unknown_weekday");
    for (let days = 0; days <= 7; days += 1) {
      const day = localDayAfter(today.year, today.month, today.day, days);
      const weekday = new Date(Date.UTC(day.year, day.month - 1, day.day))
        .getUTCDay();
      if (weekday === target && isAhead(at(day))) return at(day);
    }
    throw new Error("unreachable_weekday");
  }

  throw new Error("unknown_due_expectation");
}

export function zonedDueAt(dueAt) {
  return typeof dueAt === "string" && /(?:Z|[+-]\d{2}:\d{2})$/.test(dueAt) &&
      !Number.isNaN(Date.parse(dueAt))
    ? Date.parse(dueAt)
    : null;
}

export function dueAtExpectationMet(evalCase, schemaValid, proposals) {
  if (evalCase.must_include_due_at === true) {
    return schemaValid &&
      proposals.length > 0 &&
      proposals.every((proposal) =>
        zonedDueAt(proposal.payload?.due_at) !== null
      );
  }
  if (Object.hasOwn(evalCase, "expected_due_at")) {
    return schemaValid &&
      proposals.every((proposal) =>
        (proposal.payload?.due_at ?? null) === evalCase.expected_due_at
      );
  }
  return null;
}

export function dueAtOnExpectedLocalTime(evalCase, proposals, now) {
  if (!evalCase.expected_due_local) return null;
  const expected = expectedDueInstant(evalCase.expected_due_local, now)
    .getTime();
  const dated = proposals.filter((proposal) =>
    proposal?.kind === "task" || proposal?.kind === "reminder"
  );
  return dated.length > 0 &&
    dated.every((proposal) =>
      zonedDueAt(proposal.payload?.due_at) === expected
    );
}
