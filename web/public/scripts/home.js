const menuButton = document.querySelector("[data-menu-button]");
const mobileMenu = document.querySelector("[data-mobile-menu]");
const header = document.querySelector("[data-header]");
const dialog = document.querySelector("[data-waitlist-dialog]");
const openButtons = document.querySelectorAll("[data-open-waitlist]");
const closeButtons = document.querySelectorAll("[data-close-waitlist]");
const waitlistEntry = document.querySelector("[data-waitlist-entry]");
const waitlistSuccess = document.querySelector("[data-waitlist-success]");
const waitlistForm = document.querySelector("[data-waitlist-form]");
const waitlistStatus = document.querySelector("[data-waitlist-status]");
const waitlistSubmitLabel = document.querySelector("[data-waitlist-submit-label]");

menuButton?.addEventListener("click", () => {
  const isOpen = menuButton.getAttribute("aria-expanded") === "true";
  menuButton.setAttribute("aria-expanded", String(!isOpen));
  mobileMenu?.classList.toggle("is-open", !isOpen);
});

mobileMenu?.querySelectorAll("a").forEach((link) => {
  link.addEventListener("click", () => {
    menuButton?.setAttribute("aria-expanded", "false");
    mobileMenu.classList.remove("is-open");
  });
});

const openWaitlist = (source) => {
  mobileMenu?.classList.remove("is-open");
  menuButton?.setAttribute("aria-expanded", "false");
  if (dialog instanceof HTMLDialogElement) {
    dialog.dataset.waitlistSource = source;
    dialog.showModal();
    requestAnimationFrame(() => {
      dialog.querySelector("input[name='firstName']")?.focus();
    });
  }
};

openButtons.forEach((button) => {
  button.addEventListener("click", () => {
    openWaitlist(button.dataset.waitlistSource ?? "landing");
  });
});

if (window.location.hash === "#lista") {
  openWaitlist("invite");
}

closeButtons.forEach((button) => {
  button.addEventListener("click", () => {
    if (dialog instanceof HTMLDialogElement) dialog.close();
  });
});

dialog?.addEventListener("click", (event) => {
  if (event.target === dialog && dialog instanceof HTMLDialogElement) dialog.close();
});

const setWaitlistStatus = (message, tone = "") => {
  if (!waitlistStatus) return;
  waitlistStatus.textContent = message;
  waitlistStatus.dataset.tone = tone;
};

const resetWaitlist = () => {
  if (!(waitlistForm instanceof HTMLFormElement)) return;
  waitlistForm.reset();
  waitlistForm.removeAttribute("aria-busy");
  waitlistEntry?.removeAttribute("hidden");
  waitlistSuccess?.setAttribute("hidden", "");
  setWaitlistStatus();
};

dialog?.addEventListener("close", () => {
  window.setTimeout(resetWaitlist, 180);
});

waitlistForm?.addEventListener("submit", async (event) => {
  event.preventDefault();
  if (!(waitlistForm instanceof HTMLFormElement) || !waitlistForm.reportValidity()) return;

  const submitButton = waitlistForm.querySelector("button[type='submit']");
  const data = new FormData(waitlistForm);
  const email = String(data.get("email") ?? "");
  const firstName = String(data.get("firstName") ?? "");
  const website = String(data.get("website") ?? "");
  const consent = data.get("consent") === "on";

  if (submitButton instanceof HTMLButtonElement) submitButton.disabled = true;
  waitlistForm.setAttribute("aria-busy", "true");
  if (waitlistSubmitLabel) waitlistSubmitLabel.textContent = "Entrando...";
  setWaitlistStatus("Enviando com segurança.");

  try {
    const response = await fetch("/api/waitlist", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify({
        email,
        firstName,
        website,
        consent,
        consentVersion: waitlistForm.dataset.consentVersion ?? "",
        source: dialog?.dataset.waitlistSource ?? "landing",
        locale: navigator.language || "pt-BR",
      }),
    });

    const result = await response.json().catch(() => ({}));
    if (response.ok && result.accepted === true) {
      waitlistEntry?.setAttribute("hidden", "");
      waitlistSuccess?.removeAttribute("hidden");
      waitlistSuccess?.querySelector("button")?.focus();
      return;
    }

    if (response.status === 429) {
      setWaitlistStatus("Muitas tentativas agora. Tente novamente em uma hora.", "error");
    } else if (result.error === "invalid_email") {
      setWaitlistStatus("Confira o email e tente novamente.", "error");
    } else if (result.error === "consent_required") {
      setWaitlistStatus("Marque o consentimento para entrar na lista.", "error");
    } else {
      setWaitlistStatus("A lista está temporariamente indisponível. Tente de novo mais tarde.", "error");
    }
  } catch {
    setWaitlistStatus("Sem conexão com a lista agora. Tente novamente em instantes.", "error");
  } finally {
    if (submitButton instanceof HTMLButtonElement) submitButton.disabled = false;
    waitlistForm.removeAttribute("aria-busy");
    if (waitlistSubmitLabel) waitlistSubmitLabel.textContent = "Entrar na lista";
  }
});

// Motion is opt-in: the resting page is already the finished frame, so a reader
// who has asked for less movement is never handed an empty one.
const prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

// Measured against the viewport rather than through IntersectionObserver, which
// is silently absent in some embedded webviews and reports a ratio no element
// taller than the viewport can ever reach.
const sequences = [
  { selector: "[data-ritual]", className: "is-playing", shown: 0.2, nodes: null },
  { selector: "[data-bands]", className: "is-landing", shown: 0.4, nodes: null },
];

const armSequences = () => {
  if (prefersReducedMotion.matches) return true;

  let pending = 0;
  sequences.forEach((sequence) => {
    if (!sequence.nodes) {
      sequence.nodes = Array.from(document.querySelectorAll(sequence.selector));
    }
    sequence.nodes = sequence.nodes.filter((node) => {
      const rect = node.getBoundingClientRect();
      const reach = Math.min(rect.height, window.innerHeight);
      const shown = Math.min(rect.bottom, window.innerHeight) - Math.max(rect.top, 0);
      if (reach <= 0 || shown / reach < sequence.shown) return true;
      node.classList.add(sequence.className);
      return false;
    });
    pending += sequence.nodes.length;
  });

  return pending === 0;
};

const onScroll = () => {
  header?.classList.toggle("is-scrolled", window.scrollY > 16);
  if (armSequences()) window.removeEventListener("scroll", onScroll);
};

onScroll();
window.addEventListener("scroll", onScroll, { passive: true });
window.addEventListener("resize", armSequences, { passive: true });
