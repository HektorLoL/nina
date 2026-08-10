export type CheckStatus = "pass" | "warning" | "failure";

export interface CheckResult {
  id: string;
  status: CheckStatus;
  message: string;
}

export interface RepositoryFacts {
  bundleID: string;
  teamID: string;
  productIDs: string[];
  publicBaseURL: string;
}

export interface IOSArtifactSnapshot {
  info: Record<string, unknown>;
  archiveInfo?: Record<string, unknown>;
  files: string[];
  isArchive: boolean;
  scanComplete: boolean;
  containsServerCredential: boolean;
}

export interface PreflightEnvironment {
  [key: string]: string | undefined;
}

type Fetcher = (input: string | URL, init?: RequestInit) => Promise<Response>;

const placeholderPattern =
  /(replace|placeholder|example|changeme|todo|tbd|preencher|definir|your[-_ ]|\$\(|<[^>]+>)/i;
const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const reverseDNSPattern = /^[a-z0-9]+(?:[.-][a-z0-9]+){2,}$/i;
const localSecretPaths = [
  "Nina/Config/SupabaseSecrets.xcconfig",
  "config/production.env",
  "supabase/.env.local",
  "web/.dev.vars",
];

const premiumRecordedSaleGuard = "if didRecord {";

export function premiumTransactionFinishes(
  source: string,
): { total: number; afterServerRecord: number } {
  let depth = 0;
  let guardDepth: number | undefined;
  let total = 0;
  let afterServerRecord = 0;

  for (const line of source.split("\n")) {
    if (guardDepth === undefined && line.includes(premiumRecordedSaleGuard)) {
      guardDepth = depth;
    }
    if (line.includes("transaction.finish()")) {
      total += 1;
      if (guardDepth !== undefined) afterServerRecord += 1;
    }
    depth += countOccurrences(line, "{") - countOccurrences(line, "}");
    if (guardDepth !== undefined && depth <= guardDepth) guardDepth = undefined;
  }

  return { total, afterServerRecord };
}

function countOccurrences(value: string, character: string): number {
  let count = 0;
  for (const entry of value) {
    if (entry === character) count += 1;
  }
  return count;
}

function check(
  id: string,
  condition: boolean,
  passMessage: string,
  failureMessage: string,
): CheckResult {
  return {
    id,
    status: condition ? "pass" : "failure",
    message: condition ? passMessage : failureMessage,
  };
}

function warning(id: string, message: string): CheckResult {
  return { id, status: "warning", message };
}

function joinPath(root: string, relativePath: string): string {
  return `${root.replace(/\/$/, "")}/${relativePath}`;
}

async function readText(root: string, relativePath: string): Promise<string> {
  return await Deno.readTextFile(joinPath(root, relativePath));
}

function firstBuildSetting(source: string, name: string): string | undefined {
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return source.match(new RegExp(`${escaped} = ([^;]+);`))?.[1]?.trim();
}

function commaSeparated(value: string | undefined): string[] {
  return (value ?? "")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
}

function decodedJWTRole(value: string): string | undefined {
  const segments = value.split(".");
  if (segments.length !== 3 || segments.some((segment) => !segment)) {
    return undefined;
  }

  try {
    const normalized = segments[1]
      .replaceAll("-", "+")
      .replaceAll("_", "/")
      .padEnd(Math.ceil(segments[1].length / 4) * 4, "=");
    const payload = JSON.parse(atob(normalized));
    return typeof payload.role === "string" ? payload.role : undefined;
  } catch {
    return undefined;
  }
}

function hasPlaceholder(value: string | undefined): boolean {
  return !value?.trim() || placeholderPattern.test(value);
}

function isRootHTTPSURL(value: string | undefined): boolean {
  if (hasPlaceholder(value)) return false;
  try {
    const url = new URL(value!);
    return url.protocol === "https:" &&
      Boolean(url.hostname) &&
      !["localhost", "127.0.0.1", "::1"].includes(url.hostname) &&
      !url.username &&
      !url.password &&
      (url.pathname === "/" || url.pathname === "") &&
      !url.search &&
      !url.hash;
  } catch {
    return false;
  }
}

export function isPublishableSupabaseKey(value: string | undefined): boolean {
  const normalized = value?.trim() ?? "";
  if (hasPlaceholder(normalized) || /\s/.test(normalized)) return false;
  if (normalized.startsWith("sb_publishable_")) {
    return normalized.slice("sb_publishable_".length).length >= 16;
  }
  return decodedJWTRole(normalized) === "anon";
}

export function isSecretSupabaseKey(value: string | undefined): boolean {
  const normalized = value?.trim() ?? "";
  if (hasPlaceholder(normalized) || /\s/.test(normalized)) return false;
  if (normalized.startsWith("sb_secret_")) {
    return normalized.slice("sb_secret_".length).length >= 16;
  }
  return decodedJWTRole(normalized) === "service_role";
}

export function parseEnvironmentFile(source: string): PreflightEnvironment {
  const result: PreflightEnvironment = {};

  for (const [index, rawLine] of source.split(/\r?\n/).entries()) {
    let line = rawLine.trim();
    if (!line || line.startsWith("#")) continue;
    if (line.startsWith("export ")) line = line.slice("export ".length).trim();

    const separator = line.indexOf("=");
    if (separator <= 0) {
      throw new Error(`Invalid environment assignment on line ${index + 1}.`);
    }

    const key = line.slice(0, separator).trim();
    let value = line.slice(separator + 1).trim();
    if (!/^[A-Z][A-Z0-9_]*$/.test(key)) {
      throw new Error(`Invalid environment key on line ${index + 1}.`);
    }
    if (Object.hasOwn(result, key)) {
      throw new Error(`Duplicate environment key ${key} on line ${index + 1}.`);
    }

    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    } else {
      value = value.replace(/\s+#.*$/, "").trim();
    }
    result[key] = value;
  }

  return result;
}

export function productionEnvironmentChecks(
  environment: PreflightEnvironment,
  facts: RepositoryFacts,
): CheckResult[] {
  const value = (name: string) => environment[name]?.trim();
  const publicURL = value("NINA_PUBLIC_BASE_URL");
  const supabaseURL = value("NINA_SUPABASE_URL");
  const publishableKey = value("NINA_SUPABASE_PUBLISHABLE_KEY");
  const secretKey = value("NINA_SUPABASE_SECRET_KEY");
  const hashSalt = value("NINA_WAITLIST_HASH_SALT") ?? "";
  const openAIKey = value("OPENAI_API_KEY") ?? "";
  const products = commaSeparated(value("NINA_PREMIUM_PRODUCT_IDS"));
  const expectedProducts = [...facts.productIDs].sort();
  const uniqueSaltCharacters = new Set(hashSalt).size;

  const results: CheckResult[] = [
    check(
      "environment.public-url",
      isRootHTTPSURL(publicURL) && publicURL === facts.publicBaseURL,
      "Public base URL matches the canonical HTTPS site.",
      "Set NINA_PUBLIC_BASE_URL to the canonical repository site URL.",
    ),
    check(
      "environment.supabase-url",
      isRootHTTPSURL(supabaseURL),
      "Supabase uses a root HTTPS URL.",
      "Set NINA_SUPABASE_URL to a non-local root HTTPS URL.",
    ),
    check(
      "environment.publishable-key",
      isPublishableSupabaseKey(publishableKey),
      "The client key is publishable/anon scoped.",
      "Provide a valid sb_publishable key or legacy anon JWT.",
    ),
    check(
      "environment.secret-key",
      isSecretSupabaseKey(secretKey),
      "The Worker key is server scoped.",
      "Provide a dedicated sb_secret key or legacy service-role JWT for the Worker.",
    ),
    check(
      "environment.key-separation",
      Boolean(publishableKey && secretKey && publishableKey !== secretKey),
      "Client and server Supabase keys are distinct.",
      "Use separate client and server Supabase keys.",
    ),
    check(
      "environment.waitlist-salt",
      !hasPlaceholder(hashSalt) && hashSalt.length >= 32 &&
        uniqueSaltCharacters >= 12,
      "The waitlist abuse salt has sufficient length and variation.",
      "Generate a random waitlist salt with at least 32 characters and 12 distinct characters.",
    ),
    check(
      "environment.openai-key",
      !hasPlaceholder(openAIKey) && openAIKey.startsWith("sk-") &&
        openAIKey.length >= 32,
      "An OpenAI project key is configured for Edge Functions.",
      "Configure a non-placeholder OpenAI project key in Supabase secrets.",
    ),
    check(
      "environment.bundle-id",
      value("NINA_APP_BUNDLE_ID") === facts.bundleID,
      "App bundle identifier matches the Xcode project.",
      "Set NINA_APP_BUNDLE_ID to the Xcode app bundle identifier.",
    ),
    check(
      "environment.team-id",
      value("NINA_APPLE_TEAM_ID") === facts.teamID,
      "Apple team identifier matches signing and Universal Links.",
      "Set NINA_APPLE_TEAM_ID to the Xcode signing team identifier.",
    ),
    check(
      "environment.apple-id",
      /^[1-9][0-9]{5,}$/.test(value("NINA_APP_APPLE_ID") ?? ""),
      "A numeric App Store application identifier is configured.",
      "Set NINA_APP_APPLE_ID to the numeric App Store Connect application ID.",
    ),
    check(
      "environment.app-store-id-parity",
      value("PUBLIC_NINA_APP_STORE_ID") === value("NINA_APP_APPLE_ID"),
      "The website install link points at the same App Store listing the server verifies.",
      "Set PUBLIC_NINA_APP_STORE_ID to the same numeric ID as NINA_APP_APPLE_ID.",
    ),
    check(
      "environment.products",
      products.length > 0 &&
        products.every((product) => reverseDNSPattern.test(product)) &&
        JSON.stringify([...products].sort()) ===
          JSON.stringify(expectedProducts),
      "Premium product identifiers match the iOS release configuration.",
      "Make NINA_PREMIUM_PRODUCT_IDS exactly match the iOS product identifiers.",
    ),
    check(
      "environment.app-store-mode",
      value("NINA_APP_STORE_ENVIRONMENT") === "production" &&
        value("NINA_APP_STORE_ONLINE_CHECKS") === "true",
      "App Store verification is production-only with online checks enabled.",
      "Set App Store environment to production and online checks to true.",
    ),
    check(
      "environment.ai-release-decision",
      ["YES", "NO"].includes(value("NINA_AI_V2_ENABLED") ?? ""),
      "The Nina AI V2 release decision is explicit.",
      "Set NINA_AI_V2_ENABLED explicitly to YES or NO for this release.",
    ),
  ];

  const legalFields = [
    "PUBLIC_NINA_LEGAL_ENTITY_NAME",
    "PUBLIC_NINA_LEGAL_ENTITY_DOCUMENT",
    "PUBLIC_NINA_DPO_NAME",
  ];
  results.push(check(
    "environment.legal-identity",
    legalFields.every((name) => !hasPlaceholder(value(name))) &&
      (value("PUBLIC_NINA_LEGAL_ENTITY_DOCUMENT")?.length ?? 0) >= 8,
    "Controller and DPO identity fields are complete.",
    "Fill the production controller name/document and DPO name.",
  ));

  const privacyEmail = value("PUBLIC_NINA_PRIVACY_CONTACT_EMAIL") ?? "";
  const dpoEmail = value("PUBLIC_NINA_DPO_CONTACT_EMAIL") ?? "";
  results.push(check(
    "environment.privacy-contacts",
    emailPattern.test(privacyEmail) &&
      emailPattern.test(dpoEmail) &&
      !hasPlaceholder(privacyEmail) &&
      !hasPlaceholder(dpoEmail) &&
      privacyEmail !== "oi@ninai.app",
    "Production privacy and DPO contacts are configured.",
    "Configure monitored production privacy and DPO email addresses.",
  ));

  return results;
}

function recordValue(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined;
}

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" ? value.trim() : undefined;
}

function containsUnresolvedBuildSetting(value: unknown): boolean {
  if (typeof value === "string") {
    return value.includes("$(") || value.includes("${");
  }
  if (Array.isArray(value)) return value.some(containsUnresolvedBuildSetting);
  const record = recordValue(value);
  return record
    ? Object.values(record).some(containsUnresolvedBuildSetting)
    : false;
}

export function iosArtifactChecks(
  artifact: IOSArtifactSnapshot,
  environment: PreflightEnvironment,
  facts: RepositoryFacts,
): CheckResult[] {
  const info = artifact.info;
  const bundleID = stringValue(info.CFBundleIdentifier);
  const marketingVersion = stringValue(info.CFBundleShortVersionString);
  const buildVersion = stringValue(info.CFBundleVersion);
  const supabaseURL = stringValue(info.NINA_SUPABASE_URL);
  const publishableKey = stringValue(info.NINA_SUPABASE_PUBLISHABLE_KEY);
  const aiV2Enabled = stringValue(info.NINA_AI_V2_ENABLED)?.toUpperCase();
  const products = commaSeparated(stringValue(info.NINA_PREMIUM_PRODUCT_IDS));
  const executable = stringValue(info.CFBundleExecutable);
  const expectedProducts = [...facts.productIDs].sort();
  const archiveProperties = recordValue(
    artifact.archiveInfo?.ApplicationProperties,
  );

  const results: CheckResult[] = [
    check(
      "artifact.identity",
      bundleID === facts.bundleID,
      "The built app bundle identifier matches the release inventory.",
      "The built app bundle identifier does not match the repository release identity.",
    ),
    check(
      "artifact.version",
      /^\d+(?:\.\d+){1,2}$/.test(marketingVersion ?? "") &&
        /^[1-9]\d*$/.test(buildVersion ?? ""),
      "The built app contains a release-shaped marketing and build version.",
      "The built app has a missing or invalid marketing/build version.",
    ),
    check(
      "artifact.supabase-url",
      isRootHTTPSURL(supabaseURL) &&
        supabaseURL === environment.NINA_SUPABASE_URL?.trim(),
      "The built app contains the approved root HTTPS Supabase URL.",
      "The built app Supabase URL is missing, insecure, or differs from the approved inventory.",
    ),
    check(
      "artifact.publishable-key",
      isPublishableSupabaseKey(publishableKey) &&
        publishableKey === environment.NINA_SUPABASE_PUBLISHABLE_KEY?.trim(),
      "The built app contains only the approved publishable Supabase key.",
      "The built app Supabase key is missing, non-public, or differs from the approved inventory.",
    ),
    check(
      "artifact.products",
      JSON.stringify([...products].sort()) === JSON.stringify(expectedProducts),
      "The built StoreKit product identifiers match the release inventory.",
      "The built StoreKit product identifiers differ from the release inventory.",
    ),
    check(
      "artifact.ai-release-decision",
      aiV2Enabled === environment.NINA_AI_V2_ENABLED?.trim().toUpperCase(),
      "The built Nina AI V2 flag matches the explicit release decision.",
      "The built Nina AI V2 flag differs from the release inventory.",
    ),
    check(
      "artifact.resolved-settings",
      !containsUnresolvedBuildSetting(info),
      "The generated app plist has no unresolved build settings.",
      "The generated app plist still contains unresolved build placeholders.",
    ),
    check(
      "artifact.required-files",
      artifact.files.includes("PrivacyInfo.xcprivacy") &&
        Boolean(executable && artifact.files.includes(executable)),
      "The app executable and privacy manifest are present in the bundle.",
      "The built bundle is missing its executable or root privacy manifest.",
    ),
    check(
      "artifact.credential-scan",
      artifact.scanComplete && !artifact.containsServerCredential,
      "The complete app-bundle scan found no high-confidence server credentials.",
      artifact.scanComplete
        ? "The app bundle contains a high-confidence server credential; rotate and remove it."
        : "The app bundle credential scan exceeded its safety limit and is incomplete.",
    ),
  ];

  if (artifact.isArchive) {
    results.push(check(
      "artifact.archive-signing",
      stringValue(archiveProperties?.CFBundleIdentifier) === facts.bundleID &&
        stringValue(archiveProperties?.Team) === facts.teamID &&
        Boolean(stringValue(archiveProperties?.SigningIdentity)),
      "The archive signing metadata matches the app and Apple team.",
      "The archive is unsigned or its signing identity/team does not match the release inventory.",
    ));
  } else {
    results.push(warning(
      "artifact.archive-signing",
      "A direct .app can verify payload contents but not archive signing metadata; inspect the final .xcarchive before upload.",
    ));
  }

  return results;
}

async function trackedFiles(root: string): Promise<string[]> {
  const output = await new Deno.Command("git", {
    args: ["ls-files", "-z"],
    cwd: root,
    stdout: "piped",
    stderr: "piped",
  }).output();
  if (!output.success) throw new Error("Unable to list tracked Git files.");
  return new TextDecoder().decode(output.stdout).split("\0").filter(Boolean);
}

function looksLikeSecret(value: string): boolean {
  const supabaseCandidates = value.match(/sb_secret_[A-Za-z0-9._-]{20,}/g) ??
    [];
  if (supabaseCandidates.some((candidate) => !hasPlaceholder(candidate))) {
    return true;
  }

  const openAICandidates =
    value.match(/sk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{24,}/g) ?? [];
  if (openAICandidates.some((candidate) => !hasPlaceholder(candidate))) {
    return true;
  }
  if (/-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/.test(value)) {
    return true;
  }

  const jwtMatches =
    value.match(/[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/g) ??
      [];
  return jwtMatches.some((candidate) =>
    decodedJWTRole(candidate) === "service_role"
  );
}

async function plistJSON(path: string): Promise<Record<string, unknown>> {
  const output = await new Deno.Command("plutil", {
    args: ["-convert", "json", "-o", "-", path],
    stdout: "piped",
    stderr: "piped",
  }).output();
  if (!output.success) {
    throw new Error("Unable to decode an iOS artifact property list.");
  }

  const value = JSON.parse(new TextDecoder().decode(output.stdout));
  const record = recordValue(value);
  if (!record) {
    throw new Error("The iOS artifact property list is not a dictionary.");
  }
  return record;
}

async function firstApplicationInArchive(archivePath: string): Promise<string> {
  const applicationsPath = joinPath(archivePath, "Products/Applications");
  const applications: string[] = [];
  for await (const entry of Deno.readDir(applicationsPath)) {
    if (entry.isDirectory && entry.name.endsWith(".app")) {
      applications.push(entry.name);
    }
  }
  if (applications.length !== 1) {
    throw new Error(
      "The xcarchive must contain exactly one application bundle.",
    );
  }
  return joinPath(applicationsPath, applications[0]);
}

async function collectArtifactFiles(
  root: string,
): Promise<
  { files: string[]; scanComplete: boolean; containsServerCredential: boolean }
> {
  const files: string[] = [];
  let scannedBytes = 0;
  let scanComplete = true;
  let containsServerCredential = false;
  const maximumScannedBytes = 256 * 1024 * 1024;

  async function visit(directory: string, prefix = ""): Promise<void> {
    for await (const entry of Deno.readDir(directory)) {
      const relativePath = prefix ? `${prefix}/${entry.name}` : entry.name;
      const absolutePath = joinPath(directory, entry.name);
      if (entry.isDirectory) {
        await visit(absolutePath, relativePath);
      } else if (entry.isFile) {
        files.push(relativePath);
        if (containsServerCredential || !scanComplete) continue;
        const metadata = await Deno.stat(absolutePath);
        if (scannedBytes + metadata.size > maximumScannedBytes) {
          scanComplete = false;
          continue;
        }
        scannedBytes += metadata.size;
        const text = new TextDecoder().decode(
          await Deno.readFile(absolutePath),
        );
        if (looksLikeSecret(text)) containsServerCredential = true;
      }
    }
  }

  await visit(root);
  return { files, scanComplete, containsServerCredential };
}

export async function loadIOSArtifactSnapshot(
  inputPath: string,
): Promise<IOSArtifactSnapshot> {
  const normalizedPath = inputPath.replace(/\/$/, "");
  const isArchive = normalizedPath.endsWith(".xcarchive");
  const isApp = normalizedPath.endsWith(".app");
  if (!isArchive && !isApp) {
    throw new Error(
      "--ios-artifact must point to an .app or .xcarchive directory.",
    );
  }

  const metadata = await Deno.stat(normalizedPath);
  if (!metadata.isDirectory) {
    throw new Error("The iOS artifact path is not a directory.");
  }

  const appPath = isArchive
    ? await firstApplicationInArchive(normalizedPath)
    : normalizedPath;
  const [info, archiveInfo, scan] = await Promise.all([
    plistJSON(joinPath(appPath, "Info.plist")),
    isArchive ? plistJSON(joinPath(normalizedPath, "Info.plist")) : undefined,
    collectArtifactFiles(appPath),
  ]);

  return {
    info,
    archiveInfo,
    files: scan.files,
    isArchive,
    scanComplete: scan.scanComplete,
    containsServerCredential: scan.containsServerCredential,
  };
}

export async function repositoryChecks(
  root: string,
): Promise<{ checks: CheckResult[]; facts: RepositoryFacts }> {
  const [
    project,
    appConfig,
    entitlements,
    associationSource,
    astroConfig,
    gitignore,
    privacyManifest,
    privacyPage,
    workflow,
    privateLocalDataStore,
    appStore,
    profileStore,
    inviteLinks,
    sheets,
    ninaApp,
    premiumSubscriptionStore,
  ] = await Promise.all([
    readText(root, "Nina.xcodeproj/project.pbxproj"),
    readText(root, "Nina/Config/Nina.xcconfig"),
    readText(root, "Nina/Nina.entitlements"),
    readText(root, "web/public/.well-known/apple-app-site-association"),
    readText(root, "web/astro.config.mjs"),
    readText(root, ".gitignore"),
    readText(root, "Nina/PrivacyInfo.xcprivacy"),
    readText(root, "web/src/pages/privacidade.astro"),
    readText(root, ".github/workflows/ci.yml"),
    readText(root, "Nina/PrivateLocalDataStore.swift"),
    readText(root, "Nina/AppStore.swift"),
    readText(root, "Nina/ProfileStore.swift"),
    readText(root, "Nina/InviteLinks.swift"),
    readText(root, "Nina/Sheets.swift"),
    readText(root, "Nina/NinaApp.swift"),
    readText(root, "Nina/PremiumSubscriptionStore.swift"),
  ]);

  const bundleID = firstBuildSetting(project, "PRODUCT_BUNDLE_IDENTIFIER") ??
    "";
  const teamID = firstBuildSetting(project, "DEVELOPMENT_TEAM") ?? "";
  const productIDs = commaSeparated(
    appConfig.match(/^NINA_PREMIUM_PRODUCT_IDS\s*=\s*(.+)$/m)?.[1],
  );
  const publicBaseURL = astroConfig.match(/site:\s*["']([^"']+)["']/)?.[1] ??
    "";
  const facts = { bundleID, teamID, productIDs, publicBaseURL };
  const association = JSON.parse(associationSource);
  const associationAppIDs: string[] = association?.applinks?.details?.flatMap(
    (detail: { appIDs?: string[] }) => detail.appIDs ?? [],
  ) ?? [];
  const premiumFinishes = premiumTransactionFinishes(premiumSubscriptionStore);
  const files = await trackedFiles(root);
  const trackedLocalSecrets = localSecretPaths.filter((path) =>
    files.includes(path)
  );
  const riskyTrackedPaths = files.filter((path) =>
    /(^|\/)(?:\.env(?:\.[^/]+)?|[^/]+\.(?:p8|pem|key))$/i.test(path) &&
    !/(?:example|sample)(?:\.[^/]+)?$/i.test(path)
  );

  const secretBearingFiles: string[] = [];
  for (const path of files) {
    try {
      const metadata = await Deno.stat(joinPath(root, path));
      if (metadata.size > 2_000_000) continue;
      const source = await Deno.readTextFile(joinPath(root, path));
      if (looksLikeSecret(source)) secretBearingFiles.push(path);
    } catch {
      // Binary, removed, or unreadable tracked files are covered by path checks.
    }
  }

  const checks: CheckResult[] = [
    check(
      "repository.release-identity",
      reverseDNSPattern.test(bundleID) && /^[A-Z0-9]{10}$/.test(teamID),
      "Xcode bundle and signing team identifiers are explicit.",
      "Configure a valid app bundle identifier and ten-character Apple team ID.",
    ),
    check(
      "repository.release-version",
      /^\d+(?:\.\d+){1,2}$/.test(
        firstBuildSetting(project, "MARKETING_VERSION") ?? "",
      ) &&
        /^[1-9]\d*$/.test(
          firstBuildSetting(project, "CURRENT_PROJECT_VERSION") ?? "",
        ),
      "Marketing and build versions are release-shaped.",
      "Set a semantic marketing version and positive integer build number.",
    ),
    check(
      "repository.products",
      productIDs.length >= 1 &&
        productIDs.every((product) => reverseDNSPattern.test(product)),
      "Premium product identifiers are explicit and well formed.",
      "Configure valid reverse-DNS premium product identifiers.",
    ),
    check(
      "repository.universal-links",
      isRootHTTPSURL(publicBaseURL) &&
        entitlements.includes(`applinks:${new URL(publicBaseURL).hostname}`) &&
        associationAppIDs.includes(`${teamID}.${bundleID}`) &&
        associationSource.includes('"/invite/*"'),
      "Universal Link entitlement and AASA identity agree.",
      "Align the associated domain, AASA app ID, and invite route.",
    ),
    check(
      "repository.privacy-manifest",
      privacyManifest.includes("NSPrivacyAccessedAPICategoryUserDefaults") &&
        privacyManifest.includes("CA92.1") &&
        privacyManifest.includes("<key>NSPrivacyTracking</key>"),
      "The app privacy manifest declares current required-reason API use.",
      "Restore the privacy manifest and current required-reason declarations.",
    ),
    check(
      "repository.private-local-data",
      project.includes("PrivateLocalDataStore.swift in Sources") &&
        privateLocalDataStore.includes(
          "FileProtectionType.completeUntilFirstUserAuthentication",
        ) &&
        privateLocalDataStore.includes("isExcludedFromBackup = true") &&
        privateLocalDataStore.includes("SHA256.hash") &&
        privateLocalDataStore.includes("defaultMaximumEntryBytes") &&
        appStore.includes("PrivateLocalDataAccess.writeDataBestEffort") &&
        profileStore.includes("PrivateLocalDataAccess.writeDataBestEffort") &&
        inviteLinks.includes("PrivateLocalDataAccess.writeStringBestEffort") &&
        !appStore.includes("defaults.set(data, forKey: Self.homeKey") &&
        !profileStore.includes("defaults.set(data, forKey: Self.profileKey") &&
        !inviteLinks.includes("defaults.set(code, forKey: Self.pendingCodeKey"),
      "Sensitive local caches use opaque, bounded, protected, backup-excluded files.",
      "Restore protected local storage for household, profile, consent, and invite data.",
    ),
    check(
      "repository.local-data-erasure",
      appStore.includes("homeContextGeneration") &&
        profileStore.includes("localDataGenerations") &&
        sheets.includes("store.clearLocalData(for: userID)") &&
        sheets.includes("profileStore.clearLocalData(for: userID)") &&
        sheets.includes("PrivacyExportFileStore.write") &&
        sheets.includes("PrivacyExportFileStore.remove") &&
        sheets.includes(".onDisappear") &&
        ninaApp.includes("PrivacyExportFileStore.removeAll"),
      "Deletion invalidates stale loads and privacy exports have a bounded protected lifecycle.",
      "Restore explicit-ID deletion, stale-load invalidation, and privacy-export cleanup.",
    ),
    check(
      "repository.premium-transaction-finish",
      premiumFinishes.total >= 1 &&
        premiumFinishes.total === premiumFinishes.afterServerRecord &&
        premiumSubscriptionStore.includes("await recordOnServer("),
      "Purchased transactions are finished only after the server records them.",
      "Finish a purchased App Store transaction only where the server recorded it; an unrecognized or unrecorded product must stay in the queue.",
    ),
    check(
      "repository.secret-ignore",
      localSecretPaths.every((path) => gitignore.split(/\r?\n/).includes(path)),
      "All local production configuration files are ignored.",
      "Add every local production configuration path to .gitignore.",
    ),
    check(
      "repository.secret-paths",
      trackedLocalSecrets.length === 0 && riskyTrackedPaths.length === 0,
      "No local environment or private-key files are tracked.",
      `Remove tracked secret-bearing paths: ${
        [...trackedLocalSecrets, ...riskyTrackedPaths].join(", ")
      }`,
    ),
    check(
      "repository.secret-content",
      secretBearingFiles.length === 0,
      "No high-confidence server credentials were found in tracked text files.",
      `Rotate and remove credentials found in: ${
        secretBearingFiles.join(", ")
      }`,
    ),
    check(
      "repository.legal-metadata",
      privacyPage.includes("legalIdentity") &&
        privacyPage.includes("data-legal-status"),
      "The privacy page renders validated release legal metadata.",
      "Render the centralized legal identity and launch-status marker on the privacy page.",
    ),
    check(
      "repository.ci-preflight",
      workflow.includes("deno task preflight:repo"),
      "CI enforces repository production invariants.",
      "Add the repository preflight task to CI.",
    ),
  ];

  if (
    privacyPage.includes(
      "data-legal-status={legalIdentity.isProductionComplete",
    )
  ) {
    checks.push(warning(
      "repository.legal-values",
      "Legal values are intentionally external; production mode must prove they are complete.",
    ));
  }

  return { checks, facts };
}

async function fetchCheck(
  id: string,
  url: URL,
  fetcher: Fetcher,
): Promise<{ response?: Response; result?: CheckResult }> {
  try {
    const response = await fetcher(url, {
      headers: { "User-Agent": "Nina-Production-Preflight/1.0" },
      redirect: "follow",
      signal: AbortSignal.timeout(8_000),
    });
    return { response };
  } catch {
    return {
      result: {
        id,
        status: "failure",
        message: `Could not reach ${
          url.pathname || "/"
        } within the deployment timeout.`,
      },
    };
  }
}

export async function deploymentChecks(
  environment: PreflightEnvironment,
  facts: RepositoryFacts,
  fetcher: Fetcher = fetch,
): Promise<CheckResult[]> {
  const rawBaseURL = environment.NINA_PUBLIC_BASE_URL?.trim();
  if (!isRootHTTPSURL(rawBaseURL)) {
    return [{
      id: "deployment.base-url",
      status: "failure",
      message: "A valid public HTTPS base URL is required for online checks.",
    }];
  }

  const baseURL = new URL(rawBaseURL!);
  const paths = [
    "/",
    "/privacidade/",
    "/unsubscribe/",
    "/api/health",
    "/.well-known/apple-app-site-association",
  ];
  const outcomes = await Promise.all(
    paths.map((path) =>
      fetchCheck(`deployment.${path}`, new URL(path, baseURL), fetcher)
    ),
  );
  const failedFetches = outcomes.flatMap((outcome) =>
    outcome.result ? [outcome.result] : []
  );
  if (failedFetches.length > 0) return failedFetches;

  const [home, privacy, unsubscribe, health, association] = outcomes.map(
    (outcome) => outcome.response!,
  );
  const [homeBody, privacyBody, unsubscribeBody, healthBody, associationBody] =
    await Promise.all([
      home.text(),
      privacy.text(),
      unsubscribe.text(),
      health.text(),
      association.text(),
    ]);

  let healthJSON: { status?: string; checks?: Record<string, boolean> } = {};
  let associationJSON: {
    applinks?: { details?: Array<{ appIDs?: string[] }> };
  } = {};
  try {
    healthJSON = JSON.parse(healthBody);
  } catch {
    // The check below reports the invalid contract without exposing the body.
  }
  try {
    associationJSON = JSON.parse(associationBody);
  } catch {
    // The check below reports the invalid contract without exposing the body.
  }

  const deployedAppIDs = associationJSON.applinks?.details?.flatMap(
    (detail) => detail.appIDs ?? [],
  ) ?? [];
  const requiredHeaders = [
    ["content-security-policy", "default-src 'self'"],
    ["strict-transport-security", "max-age="],
    ["x-content-type-options", "nosniff"],
    ["x-frame-options", "DENY"],
    ["referrer-policy", "strict-origin"],
  ] as const;

  return [
    check(
      "deployment.home",
      home.ok && homeBody.includes("Nina"),
      "The production landing page is reachable.",
      "The production landing page did not return the expected content.",
    ),
    check(
      "deployment.security-headers",
      requiredHeaders.every(([name, fragment]) =>
        home.headers.get(name)?.includes(fragment)
      ),
      "Production HTML includes the required browser security headers.",
      "One or more production browser security headers are missing.",
    ),
    check(
      "deployment.health",
      health.status === 200 &&
        healthJSON.status === "ok" &&
        Object.values(healthJSON.checks ?? {}).every(Boolean),
      "The deployed Worker reports all runtime dependencies ready.",
      "The deployed /api/health contract is not fully ready.",
    ),
    check(
      "deployment.privacy",
      privacy.ok &&
        privacyBody.includes('data-legal-status="complete"') &&
        privacyBody.includes(
          environment.PUBLIC_NINA_LEGAL_ENTITY_NAME ?? "__missing__",
        ) &&
        privacyBody.includes(
          environment.PUBLIC_NINA_DPO_CONTACT_EMAIL ?? "__missing__",
        ),
      "The deployed privacy page contains the approved legal identity and contact.",
      "The deployed privacy page still has incomplete or mismatched legal metadata.",
    ),
    check(
      "deployment.unsubscribe",
      unsubscribe.ok &&
        /<meta[^>]+name=["']robots["'][^>]+noindex/i.test(unsubscribeBody),
      "The unsubscribe page is reachable and excluded from indexing.",
      "The unsubscribe page is missing or not marked noindex.",
    ),
    check(
      "deployment.universal-links",
      association.ok &&
        association.headers.get("content-type")?.includes(
            "application/json",
          ) === true &&
        deployedAppIDs.includes(`${facts.teamID}.${facts.bundleID}`),
      "The deployed AASA file matches the signed application identity.",
      "The deployed AASA file is invalid or does not match the app identity.",
    ),
  ];
}

function printResults(results: CheckResult[]): void {
  for (const result of results) {
    const label = result.status === "pass"
      ? "PASS"
      : result.status === "warning"
      ? "WARN"
      : "FAIL";
    console.log(`${label} ${result.id}: ${result.message}`);
  }

  const failures =
    results.filter((result) => result.status === "failure").length;
  const warnings =
    results.filter((result) => result.status === "warning").length;
  console.log(`\nPreflight: ${failures} failure(s), ${warnings} warning(s).`);
}

function optionValue(args: string[], name: string): string | undefined {
  const index = args.indexOf(name);
  if (index === -1) return undefined;
  const value = args[index + 1];
  if (!value || value.startsWith("--")) {
    throw new Error(`${name} requires a value.`);
  }
  return value;
}

async function main(): Promise<void> {
  const [mode = "repository", ...args] = Deno.args;
  if (!["repository", "production"].includes(mode)) {
    throw new Error(
      "Usage: production_preflight.ts repository|production [--env-file path] [--online] [--ios-artifact path] [--root path]",
    );
  }

  const root = optionValue(args, "--root") ?? Deno.cwd();
  const repository = await repositoryChecks(root);
  const results = mode === "production"
    ? repository.checks.filter((result) =>
      result.id !== "repository.legal-values"
    )
    : [...repository.checks];

  if (mode === "production") {
    const envFile = optionValue(args, "--env-file");
    let fileEnvironment: PreflightEnvironment = {};
    if (envFile) {
      const path = envFile.startsWith("/") ? envFile : joinPath(root, envFile);
      fileEnvironment = parseEnvironmentFile(await Deno.readTextFile(path));
    }
    const environment = { ...fileEnvironment, ...Deno.env.toObject() };
    results.push(...productionEnvironmentChecks(environment, repository.facts));
    const iosArtifact = optionValue(args, "--ios-artifact");
    if (iosArtifact) {
      const path = iosArtifact.startsWith("/")
        ? iosArtifact
        : joinPath(root, iosArtifact);
      const artifact = await loadIOSArtifactSnapshot(path);
      results.push(
        ...iosArtifactChecks(artifact, environment, repository.facts),
      );
    } else {
      results.push(warning(
        "artifact.ios",
        "The iOS artifact was not inspected; rerun with --ios-artifact for the final .xcarchive.",
      ));
    }
    if (args.includes("--online")) {
      results.push(...await deploymentChecks(environment, repository.facts));
    } else {
      results.push(warning(
        "deployment.online",
        "Online deployment checks were skipped; rerun production preflight with --online before release.",
      ));
    }
  }

  printResults(results);
  if (results.some((result) => result.status === "failure")) Deno.exit(1);
}

if (import.meta.main) {
  try {
    await main();
  } catch (error) {
    console.error(
      `FAIL preflight.internal: ${
        error instanceof Error ? error.message : "Unexpected preflight failure."
      }`,
    );
    Deno.exit(1);
  }
}
