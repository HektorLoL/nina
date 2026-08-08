const pathParts = window.location.pathname.split("/").filter(Boolean);
const rawCode = pathParts.at(-1) === "invite" ? "" : pathParts.at(-1) ?? "";
const code = rawCode.toLowerCase().replace(/[^a-z0-9-]/g, "");
const title = document.querySelector("[data-invite-title]");
const description = document.querySelector("[data-invite-description]");
const codeBox = document.querySelector("[data-invite-code]");
const codeValue = codeBox?.querySelector("strong");
const statusElement = document.querySelector("[data-invite-status]");
const actions = document.querySelector("[data-invite-actions]");
const openApp = document.querySelector("[data-open-app]");

const setStatus = (tone, message) => {
  if (!statusElement) return;
  const dot = document.createElement("span");
  dot.className = `status-dot ${tone}`;
  statusElement.replaceChildren(dot, document.createTextNode(` ${message}`));
};

const setOpenAppURL = () => {
  if (openApp instanceof HTMLAnchorElement) {
    openApp.href = `nina://invite/${encodeURIComponent(code)}`;
  }
};

const showError = (message) => {
  if (title) title.textContent = "Este convite não está disponível.";
  if (description) description.textContent = message;
  setStatus("error", "Convite inválido");
  codeBox?.setAttribute("hidden", "");
  actions?.setAttribute("hidden", "");
};

const showInvite = (familyName, verified, usesRemaining, expiresAt) => {
  if (title) title.textContent = `${familyName} quer você por perto.`;
  if (description) {
    description.textContent =
      "Abra a Nina para pedir entrada. Uma pessoa responsável confirma antes de você acessar a rotina.";
  }
  if (codeValue) codeValue.textContent = code;
  codeBox?.removeAttribute("hidden");
  actions?.removeAttribute("hidden");

  const details = [
    typeof usesRemaining === "number" ? `${usesRemaining} acessos disponíveis` : "",
    expiresAt
      ? `válido até ${new Intl.DateTimeFormat("pt-BR", { dateStyle: "short" }).format(new Date(expiresAt))}`
      : "",
  ].filter(Boolean);
  const message = verified
    ? `Convite confirmado${details.length ? ` · ${details.join(" · ")}` : ""}`
    : "Código pronto para usar";
  setStatus(verified ? "success" : "neutral", message);
  setOpenAppURL();
};

const showUnverified = () => {
  if (title) title.textContent = "Abra este convite na Nina.";
  if (description) {
    description.textContent =
      "Não foi possível confirmar o convite no site agora. O app fará a verificação antes de entrar.";
  }
  if (codeValue) codeValue.textContent = code;
  codeBox?.removeAttribute("hidden");
  actions?.removeAttribute("hidden");
  setStatus("neutral", "Verificação pendente");
  setOpenAppURL();
};

const copyCode = async () => {
  if (!code) return;
  try {
    await navigator.clipboard.writeText(code);
  } catch {
    return;
  }

  document.querySelectorAll("[data-copy-code]").forEach((button) => {
    const previous = button.textContent;
    if (button.textContent?.trim() === "Copiar código") button.textContent = "Copiado";
    setTimeout(() => {
      if (previous) button.textContent = previous;
    }, 1600);
  });
};

document.querySelectorAll("[data-copy-code]").forEach((button) => {
  button.addEventListener("click", copyCode);
});

if (code.length < 12) {
  showError("Peça um novo link para a pessoa que convidou você.");
} else {
  fetch(`/api/invite/${encodeURIComponent(code)}`)
    .then(async (response) => {
      const payload = await response.json();
      if (!response.ok || !payload.valid) throw new Error(payload.error ?? "invalid");
      showInvite(
        payload.familyName ?? "Uma casa na Nina",
        payload.verified === true,
        payload.usesRemaining,
        payload.expiresAt,
      );
    })
    .catch(showUnverified);
}
