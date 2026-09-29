export type AgeStatus = "adult" | "minor" | "unknown";
export type MinorBand = "under_12" | "12_15" | "16_17";
export type SignalAssurance =
  | "confirmed"
  | "self_declared"
  | "guardian_declared"
  | "none";

export type AgeDeclaration =
  | "confirmed"
  | "self_declared"
  | "guardian_declared"
  | "checked_by_other_method"
  | "guardian_checked_by_other_method"
  | "government_id_checked"
  | "guardian_government_id_checked"
  | "payment_checked"
  | "guardian_payment_checked";

export type AgeSignal = {
  declaration: AgeDeclaration | null;
  eligible_for_age_features: boolean | null;
  lower_bound: number | null;
  outcome: "sharing" | "declined";
  parental_controls: string[];
  regulatory_features: string[];
  upper_bound: number | null;
};

export type MappedAge = {
  status: AgeStatus;
  band: MinorBand | null;
  assurance: SignalAssurance;
  parentalControlsActive: boolean;
};

export const maxSignalJSONBytes = 1_024;

export const signalKeys = [
  "declaration",
  "eligible_for_age_features",
  "lower_bound",
  "outcome",
  "parental_controls",
  "regulatory_features",
  "upper_bound",
] as const;

const declarations = new Set<string>([
  "confirmed",
  "self_declared",
  "guardian_declared",
  "checked_by_other_method",
  "guardian_checked_by_other_method",
  "government_id_checked",
  "guardian_government_id_checked",
  "payment_checked",
  "guardian_payment_checked",
]);

const confirmedDeclarations = new Set<string>([
  "confirmed",
  "checked_by_other_method",
  "payment_checked",
  "government_id_checked",
]);

const parentalControls = new Set<string>([
  "communication_limits",
  "significant_app_change_approval_required",
  "other",
]);

const regulatoryFeatures = new Set<string>([
  "significant_app_change_requires_adult_notification",
  "significant_app_change_requires_parental_consent",
  "declared_age_range_required",
]);

function isBound(value: unknown): value is number | null {
  return value === null ||
    (typeof value === "number" && Number.isInteger(value) && value >= 0 &&
      value <= 150);
}

function isClosedList(value: unknown, allowed: Set<string>): value is string[] {
  return Array.isArray(value) &&
    value.length <= allowed.size &&
    value.every((entry) => typeof entry === "string" && allowed.has(entry)) &&
    new Set(value).size === value.length;
}

// The server parses exactly the bytes the device signed, and only the seven
// keys it signs; anything else is refused rather than guessed at.
export function parseAgeSignalJSON(text: string): AgeSignal | null {
  if (new TextEncoder().encode(text).byteLength > maxSignalJSONBytes) {
    return null;
  }

  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch {
    return null;
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return null;
  }

  const record = value as Record<string, unknown>;
  const keys = Object.keys(record).sort();
  if (
    keys.length !== signalKeys.length ||
    keys.some((key, index) => key !== signalKeys[index])
  ) {
    return null;
  }

  const outcome = record.outcome;
  if (outcome !== "sharing" && outcome !== "declined") return null;
  if (
    record.declaration !== null &&
    (typeof record.declaration !== "string" ||
      !declarations.has(record.declaration))
  ) {
    return null;
  }
  if (
    record.eligible_for_age_features !== null &&
    typeof record.eligible_for_age_features !== "boolean"
  ) {
    return null;
  }
  if (!isBound(record.lower_bound) || !isBound(record.upper_bound)) {
    return null;
  }
  if (
    typeof record.lower_bound === "number" &&
    typeof record.upper_bound === "number" &&
    record.lower_bound > record.upper_bound
  ) {
    return null;
  }
  if (
    !isClosedList(record.parental_controls, parentalControls) ||
    !isClosedList(record.regulatory_features, regulatoryFeatures)
  ) {
    return null;
  }
  if (
    outcome === "declined" &&
    (record.declaration !== null || record.lower_bound !== null ||
      record.upper_bound !== null)
  ) {
    return null;
  }

  return {
    declaration: record.declaration as AgeDeclaration | null,
    eligible_for_age_features: record.eligible_for_age_features as
      | boolean
      | null,
    lower_bound: record.lower_bound as number | null,
    outcome,
    parental_controls: record.parental_controls as string[],
    regulatory_features: record.regulatory_features as string[],
    upper_bound: record.upper_bound as number | null,
  };
}

// The youngest band a range overlaps decides, the declaration only decides
// how sure the answer is, and eligible_for_age_features never decides at all.
export function mapAgeRange(signal: AgeSignal): MappedAge {
  if (signal.outcome === "declined") {
    return {
      status: "unknown",
      band: null,
      assurance: "none",
      parentalControlsActive: false,
    };
  }

  const lowerBound = signal.lower_bound ?? 0;
  const parentalControlsActive = signal.parental_controls.length > 0;
  const declaration = signal.declaration;

  if (lowerBound >= 18) {
    return {
      status: "adult",
      band: null,
      assurance: declaration && confirmedDeclarations.has(declaration)
        ? "confirmed"
        : "self_declared",
      parentalControlsActive,
    };
  }

  const band: MinorBand = lowerBound < 12
    ? "under_12"
    : lowerBound < 16
    ? "12_15"
    : "16_17";
  let assurance: SignalAssurance = "none";
  if (declaration && confirmedDeclarations.has(declaration)) {
    assurance = "confirmed";
  } else if (declaration?.startsWith("guardian_")) {
    assurance = "guardian_declared";
  } else if (declaration === "self_declared") {
    assurance = "self_declared";
  }

  return { status: "minor", band, assurance, parentalControlsActive };
}
