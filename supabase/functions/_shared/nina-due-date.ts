import type { NinaProposalOutput } from "./nina-ai.ts";

export const ninaTimeZone = "America/Sao_Paulo";
export const ninaDefaultDueHour = 9;
export const ninaDefaultDueTime = `${
  String(ninaDefaultDueHour).padStart(2, "0")
}:00`;

export type NinaLocalNow = {
  date: string;
  weekday: string;
  time: string;
  utc_offset: string;
  time_zone: string;
};

export type DueAtFill = { proposals: NinaProposalOutput[]; filled: number };

type LocalDay = { year: number; month: number; day: number };
type WallClock = LocalDay & { hour: number; minute: number; second: number };
type ClockTime = { hour: number; minute: number };

type DateWord =
  | { kind: "pinned"; days: number }
  | { kind: "monthDay"; day: number; month: number; year: number | null }
  | { kind: "dayOfMonth"; day: number; nextMonth: boolean }
  | { kind: "weekday"; weekday: number; notToday: boolean };

type DueWords = { dates: DateWord[]; time: ClockTime | null };

const localWeekdayNames = [
  "domingo",
  "segunda-feira",
  "terça-feira",
  "quarta-feira",
  "quinta-feira",
  "sexta-feira",
  "sábado",
];

const wallClockFormatter = new Intl.DateTimeFormat("en-US", {
  timeZone: ninaTimeZone,
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
  second: "2-digit",
  hourCycle: "h23",
});

const monthNumbers: Record<string, number> = {
  janeiro: 1,
  fevereiro: 2,
  marco: 3,
  abril: 4,
  maio: 5,
  junho: 6,
  julho: 7,
  agosto: 8,
  setembro: 9,
  outubro: 10,
  novembro: 11,
  dezembro: 12,
  jan: 1,
  fev: 2,
  mar: 3,
  abr: 4,
  mai: 5,
  jun: 6,
  jul: 7,
  ago: 8,
  set: 9,
  out: 10,
  nov: 11,
  dez: 12,
};

const weekdayNumbers: Record<string, number> = {
  domingo: 0,
  segunda: 1,
  terca: 2,
  quarta: 3,
  quinta: 4,
  sexta: 5,
  sabado: 6,
};

const weekdayMarkers = new Set([
  "na",
  "no",
  "nesta",
  "neste",
  "nessa",
  "nesse",
  "esta",
  "este",
  "essa",
  "esse",
  "desta",
  "deste",
  "dessa",
  "desse",
  "de",
  "pra",
  "para",
  "proxima",
  "proximo",
  "ate",
  "toda",
  "todo",
]);

const durationPattern =
  /\b(?:a cada|cada|daqui(?: a)?|em|por|durante|ha|faz|dentro de|umas?|uns)\s+\d{1,3}\s*(?:h|hs|horas?|min|minutos?)\b|\bde\s+\d{1,3}\s+horas?\b|\b\d{1,2}\s*\/\s*\d{1,2}\s*h\b|\b\d{1,3}\s*(?:h|hs|horas?)\s+(?:antes|depois|seguidas|por dia)\b/;
const alternativePattern =
  /\bdia \d{1,2} (?:ou|e|a|ate) \d{1,2}(?!\d)|\b\d{1,2}(?:h\d{0,2})? ?(?:ou|e|a|ate) (?:as )?\d{1,2} ?(?:h|horas?)\b|\bentre (?:as |os dias |o dia |dia )?\d{1,2}(?!\d)|\bdas \d{1,2}(?:h\d{0,2})? (?:as|a|ate) \d{1,2}(?!\d)|\b\d{1,2}h \d{2}\b/;
const noonPattern = /\bmeio[- ]?dia( e meia)?\b/g;
const partOfDayTimePattern =
  /\b(\d{1,2})(?:h(\d{2})?|:(\d{2}))?(?:min)?\s*(?:horas?\s*)?d[ae] (manha|tarde|noite)\b/g;
const hourMinutePattern = /\b(\d{1,2})(?:h|:)(\d{2})(?:h|min)?\b/g;
const wholeHourPattern = /\b(\d{1,2}) ?(?:hs?|horas?)\b/g;
const bareHourPattern =
  /\bas (\d{1,2})\b(?=\s*(?:$|[,.;!?)]|(?:de |da )?(?:hoje|amanha|depois|dia|na|no|nesta|neste|nessa|nesse|esta|este|proxim[ao]|segunda|terca|quarta|quinta|sexta|sabado|domingo)\b))/g;
const afterTomorrowPattern = /\bdepois de amanha\b/g;
const tomorrowPattern = /\bamanha\b/g;
const todayPattern = /\bhoje\b/g;
const daysAheadPattern = /\b(?:daqui (?:a )?|em )(\d{1,3}) dias?\b/g;
const numericDatePattern =
  /\b(?:(dia|em|ate|para|no dia) )?(\d{1,2})o?\/(\d{1,2})(?:\/(\d{4}|\d{2}))?\b/g;
const namedMonthPattern =
  /\b(?:dia )?(\d{1,2})o? (?:de )?(janeiro|fevereiro|marco|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro|jan|fev|mar|abr|mai|jun|jul|ago|set|out|nov|dez)\b\.?(?: de (\d{4}))?/g;
const dayOfMonthPattern =
  /\bdia (\d{1,2})o?\b( do (?:mes que vem|proximo mes))?/g;
const weekdayPattern =
  /\b(domingo|segunda|terca|quarta|quinta|sexta|sabado)(-feira| feira)?( que vem)?\b/g;
const ordinalWeekdayPattern =
  /\b([2-6])(?:ª([ -]?feira)?|a([ -]?feira))( que vem)?(?=$|[\s,.;!?)])/g;
const ordinalNounPattern =
  /^ (?:via|vez|serie|ano|parcela|parte|dose|opcao|etapa|fase|prestacao|mensalidade|semana|turma|chamada|colocad[ao]|lugar|edicao|chance|mao)\b/;
const weekdayTimePattern =
  /^,? (?:as \d{1,2}|\d{1,2} ?(?:hs?\b|h\d|:|horas?\b|da ))/;
const strayHourPattern = /\bas \d{1,2}\b/;
const periodWordPattern =
  /\b(?:ontem|anteontem|semana|mes|quinzena|feriado|seg|qua|qui|sex|sab|dom)\b/;
const partOfDayPattern = /\b(?:tarde|noite|madrugada)\b/;
const givenInstantPattern =
  /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,9})?)?(Z|[+-]\d{2}:\d{2})?$/;

function pad2(value: number): string {
  return String(value).padStart(2, "0");
}

function wallClock(instant: Date): WallClock {
  const parts = Object.fromEntries(
    wallClockFormatter.formatToParts(instant).map((part) => [
      part.type,
      part.value,
    ]),
  );
  return {
    year: Number(parts.year),
    month: Number(parts.month),
    day: Number(parts.day),
    hour: Number(parts.hour),
    minute: Number(parts.minute),
    second: Number(parts.second),
  };
}

function offsetMinutes(instant: Date): number {
  const wall = wallClock(instant);
  const wallAsUTC = Date.UTC(
    wall.year,
    wall.month - 1,
    wall.day,
    wall.hour,
    wall.minute,
    wall.second,
  );
  const wholeSeconds = Math.floor(instant.getTime() / 1000) * 1000;
  return Math.round((wallAsUTC - wholeSeconds) / 60_000);
}

function offsetText(minutes: number): string {
  const sign = minutes < 0 ? "-" : "+";
  const magnitude = Math.abs(minutes);
  return `${sign}${pad2(Math.floor(magnitude / 60))}:${pad2(magnitude % 60)}`;
}

function localDayText(day: LocalDay): string {
  return `${String(day.year).padStart(4, "0")}-${pad2(day.month)}-${
    pad2(day.day)
  }`;
}

function instantAt(day: LocalDay, time: ClockTime): Date {
  const wallAsUTC = Date.UTC(
    day.year,
    day.month - 1,
    day.day,
    time.hour,
    time.minute,
  );
  const firstGuess = wallAsUTC - offsetMinutes(new Date(wallAsUTC)) * 60_000;
  return new Date(
    wallAsUTC - offsetMinutes(new Date(firstGuess)) * 60_000,
  );
}

function addDays(day: LocalDay, days: number): LocalDay {
  const shifted = new Date(Date.UTC(day.year, day.month - 1, day.day + days));
  return {
    year: shifted.getUTCFullYear(),
    month: shifted.getUTCMonth() + 1,
    day: shifted.getUTCDate(),
  };
}

function daysInMonth(year: number, month: number): number {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

function weekdayOf(day: LocalDay): number {
  return new Date(Date.UTC(day.year, day.month - 1, day.day)).getUTCDay();
}

export function ninaLocalNow(now: Date): NinaLocalNow {
  const wall = wallClock(now);
  return {
    date: localDayText(wall),
    weekday: localWeekdayNames[weekdayOf(wall)],
    time: `${pad2(wall.hour)}:${pad2(wall.minute)}`,
    utc_offset: offsetText(offsetMinutes(now)),
    time_zone: ninaTimeZone,
  };
}

export function ninaDueAt(instant: Date): string {
  const wall = wallClock(instant);
  return `${localDayText(wall)}T${pad2(wall.hour)}:${pad2(wall.minute)}:${
    pad2(wall.second)
  }${offsetText(offsetMinutes(instant))}`;
}

export function ninaDueLabel(instant: Date): string {
  const wall = wallClock(instant);
  return `${pad2(wall.day)}/${pad2(wall.month)}, ${pad2(wall.hour)}:${
    pad2(wall.minute)
  }`;
}

function foldDueText(text: string): string {
  return text
    .normalize("NFC")
    .toLocaleLowerCase("pt-BR")
    .replace(/[º°]/g, "")
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .replace(/\s+/g, " ")
    .trim();
}

function readDueWords(label: string): DueWords | null {
  const folded = foldDueText(label);
  if (durationPattern.test(folded) || alternativePattern.test(folded)) {
    return null;
  }

  let text = folded;
  let invalid = false;
  const times: ClockTime[] = [];
  const dates: DateWord[] = [];
  const consume = (
    pattern: RegExp,
    read: (match: RegExpMatchArray) => void,
  ) => {
    const matches = [...text.matchAll(pattern)];
    for (const match of matches) {
      read(match);
      const start = match.index ?? 0;
      text = text.slice(0, start) + " ".repeat(match[0].length) +
        text.slice(start + match[0].length);
    }
  };
  const pushTime = (hour: number, minute: number) => {
    if (hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59) {
      times.push({ hour, minute });
    } else {
      invalid = true;
    }
  };

  consume(noonPattern, (match) => pushTime(12, match[1] ? 30 : 0));
  consume(numericDatePattern, (match) => {
    const marked = match[1] === "dia" || match[1] === "no dia";
    const year = match[4] === undefined
      ? null
      : Number(match[4]) + (match[4].length === 2 ? 2000 : 0);
    // A word that is also an ordinal, a fraction or an article counts as a date only in a date's context.
    if (!marked && year === null && match[3].length < 2) return;
    dates.push({
      kind: "monthDay",
      day: Number(match[2]),
      month: Number(match[3]),
      year,
    });
  });
  consume(namedMonthPattern, (match) => {
    dates.push({
      kind: "monthDay",
      day: Number(match[1]),
      month: monthNumbers[match[2]],
      year: match[3] === undefined ? null : Number(match[3]),
    });
  });
  consume(dayOfMonthPattern, (match) => {
    dates.push({
      kind: "dayOfMonth",
      day: Number(match[1]),
      nextMonth: match[2] !== undefined,
    });
  });
  consume(partOfDayTimePattern, (match) => {
    const hour = Number(match[1]);
    const minute = Number(match[2] ?? match[3] ?? "0");
    if (match[4] === "manha") pushTime(hour, minute);
    else if (hour >= 1 && hour <= 11) pushTime(hour + 12, minute);
    else if (hour >= 13 && hour <= 23) pushTime(hour, minute);
    else invalid = true;
  });
  consume(
    hourMinutePattern,
    (match) => pushTime(Number(match[1]), Number(match[2])),
  );
  consume(wholeHourPattern, (match) => pushTime(Number(match[1]), 0));
  consume(bareHourPattern, (match) => {
    const hour = Number(match[1]);
    // A bare "às 5" means 17h as often as 5h, so an hour from one to seven is never guessed.
    if (hour >= 1 && hour <= 7) invalid = true;
    else pushTime(hour, 0);
  });

  consume(afterTomorrowPattern, () => dates.push({ kind: "pinned", days: 2 }));
  consume(tomorrowPattern, () => dates.push({ kind: "pinned", days: 1 }));
  consume(todayPattern, () => dates.push({ kind: "pinned", days: 0 }));
  consume(daysAheadPattern, (match) => {
    dates.push({ kind: "pinned", days: Number(match[1]) });
  });

  let unplacedWeekday = false;
  const readWeekday = (
    match: RegExpMatchArray,
    weekday: number,
    hasFeira: boolean,
    hasQueVem: boolean,
    alwaysPlaced: boolean,
  ) => {
    const start = match.index ?? 0;
    const before = folded.slice(0, start).trimEnd();
    const previous = before.split(" ").at(-1) ?? "";
    const after = folded.slice(start + match[0].length);
    // A word that is also an ordinal, a fraction or an article counts as a date only in a date's context.
    if (!hasFeira && ordinalNounPattern.test(after)) return;
    const placed = alwaysPlaced || hasFeira || hasQueVem ||
      weekdayMarkers.has(previous) || before.length === 0 ||
      weekdayTimePattern.test(after);
    if (!placed) {
      unplacedWeekday = true;
      return;
    }
    dates.push({
      kind: "weekday",
      weekday,
      notToday: hasQueVem || previous.startsWith("proxim"),
    });
  };
  for (const match of folded.matchAll(weekdayPattern)) {
    readWeekday(
      match,
      weekdayNumbers[match[1]],
      match[2] !== undefined,
      match[3] !== undefined,
      match[1] === "sabado" || match[1] === "domingo",
    );
  }
  for (const match of folded.matchAll(ordinalWeekdayPattern)) {
    readWeekday(
      match,
      Number(match[1]) - 1,
      match[2] !== undefined || match[3] !== undefined,
      match[4] !== undefined,
      false,
    );
  }

  // A date or time word the reader cannot place refuses the whole text; it never falls back to today.
  if (
    invalid || unplacedWeekday || times.length > 1 ||
    strayHourPattern.test(text) || periodWordPattern.test(text) ||
    (times.length === 0 && partOfDayPattern.test(text))
  ) {
    return null;
  }
  if (dates.length === 0 && times.length === 0) return null;
  return { dates, time: times[0] ?? null };
}

function resolveDate(
  word: DateWord,
  today: LocalDay,
  time: ClockTime,
  now: Date,
): Date | null {
  const isAhead = (instant: Date) => instant.getTime() > now.getTime();
  const pinnedDay = (day: LocalDay): Date | null => {
    const instant = instantAt(day, time);
    // A day pinned to today whose default hour has passed is dated at confirmation, never at proposal time.
    return isAhead(instant) ? instant : null;
  };

  switch (word.kind) {
    case "pinned":
      return word.days > 366 ? null : pinnedDay(addDays(today, word.days));
    case "dayOfMonth": {
      if (word.day < 1 || word.day > 31) return null;
      for (let step = word.nextMonth ? 1 : 0; step < 13; step += 1) {
        const year = today.year + Math.floor((today.month - 1 + step) / 12);
        const month = ((today.month - 1 + step) % 12) + 1;
        if (word.nextMonth) {
          return word.day <= daysInMonth(year, month)
            ? instantAt({ year, month, day: word.day }, time)
            : null;
        }
        if (word.day <= daysInMonth(year, month)) {
          const instant = instantAt({ year, month, day: word.day }, time);
          if (isAhead(instant)) return instant;
        }
      }
      return null;
    }
    case "monthDay": {
      if (word.month < 1 || word.month > 12 || word.day < 1) return null;
      if (word.year !== null) {
        if (word.day > daysInMonth(word.year, word.month)) return null;
        return pinnedDay({ year: word.year, month: word.month, day: word.day });
      }
      if (word.month === today.month && word.day === today.day) {
        return pinnedDay(today);
      }
      for (let year = today.year; year < today.year + 9; year += 1) {
        if (word.day <= daysInMonth(year, word.month)) {
          const instant = instantAt(
            { year, month: word.month, day: word.day },
            time,
          );
          if (isAhead(instant)) return instant;
        }
      }
      return null;
    }
    case "weekday": {
      let days = (word.weekday - weekdayOf(today) + 7) % 7;
      if (
        days === 0 && (word.notToday || !isAhead(instantAt(today, time)))
      ) {
        days = 7;
      }
      return instantAt(addDays(today, days), time);
    }
  }
}

export function resolveDueInstant(text: string, now: Date): Date | null {
  const words = readDueWords(text);
  if (!words) return null;
  const today = wallClock(now);
  const time = words.time ?? { hour: ninaDefaultDueHour, minute: 0 };
  if (words.dates.length === 0) {
    const todayAt = instantAt(today, time);
    return todayAt.getTime() > now.getTime()
      ? todayAt
      : instantAt(addDays(today, 1), time);
  }
  const resolved = words.dates.map((word) =>
    resolveDate(word, today, time, now)
  );
  const first = resolved[0]?.getTime() ?? null;
  return resolved.every((instant) => (instant?.getTime() ?? null) === first)
    ? resolved[0]
    : null;
}

function givenInstant(value: unknown): Date | null {
  if (typeof value !== "string") return null;
  const match = givenInstantPattern.exec(value);
  if (!match) return null;
  const [year, month, day, hour, minute] = match.slice(1, 6).map(Number);
  const second = Number(match[6] ?? "0");
  const wall = new Date(Date.UTC(year, month - 1, day, hour, minute, second));
  const roundTrips = wall.getUTCFullYear() === year &&
    wall.getUTCMonth() === month - 1 && wall.getUTCDate() === day &&
    wall.getUTCHours() === hour && wall.getUTCMinutes() === minute &&
    wall.getUTCSeconds() === second;
  if (!roundTrips) return null;

  const zone = match[7];
  if (zone === undefined) {
    // Nina writes São Paulo wall time; without a zone Postgres would read it as UTC, three hours early.
    return new Date(
      instantAt({ year, month, day }, { hour, minute }).getTime() +
        second * 1000,
    );
  }
  const zoneHours = zone === "Z" ? 0 : Number(zone.slice(1, 3));
  const zoneMinutes = zone === "Z" ? 0 : Number(zone.slice(4, 6));
  const offset = (zone.startsWith("-") ? -1 : 1) *
    (zoneHours * 60 + zoneMinutes);
  if (zoneMinutes > 59 || Math.abs(offset) > 14 * 60) return null;
  return new Date(wall.getTime() - offset * 60_000);
}

export function fillMissingDueAt(
  proposals: NinaProposalOutput[],
  message: string,
  now: Date,
): DueAtFill {
  const isDatedKind = (kind: NinaProposalOutput["kind"]) =>
    kind === "task" || kind === "reminder";
  const datedCount =
    proposals.filter((proposal) => isDatedKind(proposal.kind)).length;
  let filled = 0;

  const dated = proposals.map((proposal): NinaProposalOutput => {
    const payload = { ...proposal.payload };
    if (!isDatedKind(proposal.kind)) return { ...proposal, payload };

    const given = givenInstant(payload.due_at);
    if (given) {
      // A date Nina gave is never moved; only its spelling changes, so the phone reads the instant Postgres stores.
      return { ...proposal, payload: { ...payload, due_at: ninaDueAt(given) } };
    }

    const fromLabel = resolveDueInstant(payload.due_label, now);
    if (fromLabel) {
      filled += 1;
      return {
        ...proposal,
        payload: { ...payload, due_at: ninaDueAt(fromLabel) },
      };
    }

    const fromMessage = datedCount === 1
      ? resolveDueInstant(message, now)
      : null;
    if (fromMessage) {
      filled += 1;
      return {
        ...proposal,
        payload: {
          ...payload,
          due_at: ninaDueAt(fromMessage),
          due_label: ninaDueLabel(fromMessage),
        },
      };
    }

    return { ...proposal, payload: { ...payload, due_at: null } };
  });

  return { proposals: dated, filled };
}
