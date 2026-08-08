(() => {
  const card = document.querySelector("[data-unsubscribe-card]");
  const title = document.querySelector("[data-unsubscribe-title]");
  const description = document.querySelector(
    "[data-unsubscribe-description]",
  );
  const submitButton = document.querySelector("[data-unsubscribe-submit]");
  const submitLabel = submitButton?.querySelector("span");
  const homeLink = document.querySelector("[data-unsubscribe-home]");

  if (
    !(card instanceof HTMLElement) ||
    !(title instanceof HTMLElement) ||
    !(description instanceof HTMLElement) ||
    !(submitButton instanceof HTMLButtonElement) ||
    !(submitLabel instanceof HTMLElement) ||
    !(homeLink instanceof HTMLAnchorElement)
  ) {
    return;
  }

  let token = "";
  try {
    token = decodeURIComponent(window.location.hash.slice(1)).trim()
      .toLowerCase();
  } catch {
    token = "";
  }

  // Fragments do not reach the server; remove the capability from browser history too.
  window.history.replaceState(null, "", window.location.pathname);

  const setState = (state, heading, message) => {
    card.dataset.state = state;
    card.setAttribute("aria-busy", state === "loading" ? "true" : "false");
    title.textContent = heading;
    description.textContent = message;
  };

  const showInvalidLink = () => {
    token = "";
    setState(
      "error",
      "Este link não está completo.",
      "Abra novamente o link recebido por email ou fale com a Nina para retirar seu consentimento.",
    );
    submitButton.hidden = true;
    homeLink.textContent = "Voltar para a Nina";
  };

  if (!/^[0-9a-f]{64}$/.test(token)) {
    showInvalidLink();
    return;
  }

  setState(
    "confirm",
    "Quer parar de receber novidades?",
    "Confirme abaixo para retirar o consentimento desta inscrição na lista de lançamento.",
  );
  submitButton.disabled = false;

  submitButton.addEventListener("click", async () => {
    if (!token || submitButton.disabled) return;

    setState(
      "loading",
      "Atualizando suas preferências...",
      "Aguarde enquanto concluímos sua solicitação.",
    );
    submitButton.disabled = true;
    submitLabel.textContent = "Atualizando";

    try {
      const response = await fetch("/api/waitlist/unsubscribe", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ token }),
      });
      const result = await response.json();

      if (!response.ok || result?.accepted !== true) {
        throw new Error("unsubscribe_failed");
      }

      token = "";
      setState(
        "success",
        "Preferências atualizadas.",
        "As preferências vinculadas a este link foram atualizadas. Se você recebeu um email mais recente, use o link dele também.",
      );
      submitButton.hidden = true;
      homeLink.textContent = "Voltar para a Nina";
    } catch {
      setState(
        "error",
        "Não foi possível concluir.",
        "Sua preferência não mudou. Tente novamente em alguns instantes.",
      );
      submitLabel.textContent = "Tentar novamente";
      submitButton.disabled = false;
    }
  });
})();
