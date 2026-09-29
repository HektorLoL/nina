export type NinaRatingCode = "L" | "10" | "12" | "14" | "16" | "18";

export interface NinaRatingDescription {
  code: NinaRatingCode;
  name: string;
  symbolText: string;
  accessibilityLabel: string;
  termsPhrase: string;
  colorHex: string;
}

// This line must equal `NinaRating.currentCode` in `Nina/NinaRating.swift`; the preflight compares them.
export const ninaRatingCode: NinaRatingCode = "L";

const colorHexByCode: Readonly<Record<NinaRatingCode, string>> = {
  L: "#00A859",
  "10": "#0095DA",
  "12": "#FDC300",
  "14": "#F58220",
  "16": "#E3001B",
  "18": "#1D1D1B",
};

export function ratingFor(code: NinaRatingCode): NinaRatingDescription {
  const colorHex = colorHexByCode[code];
  if (code === "L") {
    return {
      code,
      name: "Livre",
      symbolText: "L",
      accessibilityLabel: "Classificação indicativa: livre",
      termsPhrase: "livre",
      colorHex,
    };
  }

  return {
    code,
    name: `Não recomendado para menores de ${code} anos`,
    symbolText: code,
    accessibilityLabel:
      `Classificação indicativa: não recomendado para menores de ${code} anos`,
    termsPhrase: `não recomendada para menores de ${code} anos`,
    colorHex,
  };
}

export const ninaRating: NinaRatingDescription = ratingFor(ninaRatingCode);
