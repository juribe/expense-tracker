(() => {
  if (window.yogastoWebauthnUiLoaded) return;
  window.yogastoWebauthnUiLoaded = true;

  const errorText = (error) => {
    if (error && error.name === "NotAllowedError") {
      return "La operación se canceló o el tiempo de espera terminó. Inténtalo nuevamente.";
    }
    return "No pudimos completar la verificación con Passkey. Inténtalo nuevamente.";
  };

  const showMessage = (text) => {
    document.querySelectorAll("[data-webauthn-errors]").forEach((node) => {
      node.textContent = text;
      node.hidden = false;
    });

    const host = document.querySelector("[data-webauthn-errors]");
    if (host || !text) return;

    const form = document.querySelector("webauthn-get, webauthn-create")?.closest("form");
    if (!form) return;

    const alert = document.createElement("div");
    alert.className = "alert alert-danger auth-alert";
    alert.setAttribute("role", "alert");
    alert.textContent = text;
    form.prepend(alert);
  };

  document.addEventListener("webauthn:unsupported", (event) => {
    const action = event.detail && event.detail.action;
    const selector = action === "create" ? "[data-testid='passkey-form'], [data-testid='two-factor-form']" : "[data-testid='passkey-login']";
    document.querySelectorAll(selector).forEach((element) => element.classList.add("d-none"));
    showMessage(
      "Este navegador no permite usar passkeys o llaves de seguridad. Puedes continuar con tu correo y contraseña."
    );
  });

  document.addEventListener("webauthn:prompt:error", (event) => {
    event.preventDefault();
    showMessage(errorText(event.detail && event.detail.error));
  });
})();
