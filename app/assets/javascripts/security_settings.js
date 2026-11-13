(() => {
  if (window.yogastoSecuritySettingsLoaded) return;
  window.yogastoSecuritySettingsLoaded = true;

  const codes = () =>
    Array.from(document.querySelectorAll("[data-recovery-code]"))
      .map((element) => element.textContent.trim())
      .filter(Boolean);

  const codesAsText = () => codes().join("\n");

  const copyText = async (text) => {
    try {
      await navigator.clipboard.writeText(text);
    } catch (_error) {
      const textarea = document.createElement("textarea");
      textarea.value = text;
      textarea.setAttribute("readonly", "");
      textarea.style.position = "absolute";
      textarea.style.left = "-9999px";
      document.body.appendChild(textarea);
      textarea.select();
      document.execCommand("copy");
      textarea.remove();
    }
  };

  const flashButtonLabel = (button, label) => {
    const original = button.textContent;
    button.textContent = label;
    window.setTimeout(() => {
      button.textContent = original;
    }, 2500);
  };

  const copyCodes = async (button) => {
    const text = codesAsText();
    if (!text) return;

    await copyText(text);
    flashButtonLabel(button, "Códigos copiados");
  };

  const copyTotpSecret = async (button) => {
    const secret = document.querySelector("[data-totp-secret]")?.textContent.replace(/\s+/g, "");
    if (!secret) return;

    await copyText(secret);
    flashButtonLabel(button, "Clave copiada");
  };

  const downloadCodes = () => {
    const text = codesAsText();
    if (!text) return;

    const content = `Yogasto - Códigos de recuperación\n\n${text}\n\nGuarda este archivo en un lugar seguro. Cada código se puede usar una sola vez.\n`;
    const blob = new Blob([content], { type: "text/plain;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = "yogasto-codigos-de-recuperacion.txt";
    document.body.appendChild(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(url);
  };

  const confirmationModal = document.querySelector("[data-testid='security-confirmation-modal']");
  const confirmationForm = confirmationModal?.querySelector("[data-security-confirmation-form]");
  const confirmationTitle = confirmationModal?.querySelector("[data-security-confirmation-title]");
  const confirmationSubmit = confirmationModal?.querySelector("[data-security-confirmation-submit]");
  const totpChoice = confirmationModal?.querySelector("[data-security-totp-choice]");
  const recoveryChoice = confirmationModal?.querySelector("[data-security-recovery-choice]");
  const totpInput = confirmationModal?.querySelector("input[name='totp_code']");
  const recoveryInput = confirmationModal?.querySelector("input[name='recovery_code']");
  const webauthnError = document.querySelector("[data-security-webauthn-error]");
  let pendingSecurityAction;

  const showWebauthnError = (error) => {
    if (!webauthnError) return;

    webauthnError.textContent = error?.name === "NotAllowedError"
      ? webauthnError.dataset.cancelledMessage
      : webauthnError.dataset.defaultMessage;
    webauthnError.hidden = false;
  };

  const setConfirmationChoice = (choice) => {
    const usingRecovery = choice === "recovery";
    totpChoice?.classList.toggle("d-none", usingRecovery);
    recoveryChoice?.classList.toggle("d-none", !usingRecovery);
    if (totpInput) {
      totpInput.disabled = usingRecovery;
      totpInput.required = !usingRecovery;
      if (usingRecovery) totpInput.value = "";
    }
    if (recoveryInput) {
      recoveryInput.disabled = !usingRecovery;
      recoveryInput.required = usingRecovery;
      if (!usingRecovery) recoveryInput.value = "";
    }
  };

  const showSecurityConfirmation = (form) => {
    if (!confirmationModal || !confirmationForm || !window.bootstrap?.Modal) return;

    pendingSecurityAction = form;
    confirmationForm.reset();
    setConfirmationChoice("totp");
    if (confirmationTitle) {
      confirmationTitle.textContent = form.dataset.securityConfirmationTitle || "Confirma este cambio";
    }
    if (confirmationSubmit) {
      confirmationSubmit.textContent = form.dataset.securityConfirmationAction || "Confirmar cambio";
      confirmationSubmit.classList.toggle("btn-danger", form.dataset.securityConfirmationDanger === "true");
      confirmationSubmit.classList.toggle("btn-primary", form.dataset.securityConfirmationDanger !== "true");
    }

    window.bootstrap.Modal.getOrCreateInstance(confirmationModal).show();
  };

  const appendSecondFactor = (form, name, value) => {
    const input = document.createElement("input");
    input.type = "hidden";
    input.name = name;
    input.value = value;
    input.dataset.securityConfirmationValue = "true";
    form.appendChild(input);
  };

  document.addEventListener("submit", (event) => {
    const form = event.target;
    if (!(form instanceof HTMLFormElement) || form.dataset.securityConfirmation !== "true") return;

    if (form.dataset.securityConfirmationSubmitted === "true") {
      delete form.dataset.securityConfirmationSubmitted;
      return;
    }

    event.preventDefault();
    event.stopImmediatePropagation();
    showSecurityConfirmation(form);
  }, true);

  document.addEventListener("webauthn:prompt:error", (event) => {
    event.preventDefault();
    showWebauthnError(event.detail?.error);
  });

  document.addEventListener("click", (event) => {
    const copyButton = event.target.closest("[data-recovery-copy]");
    if (copyButton) {
      event.preventDefault();
      copyCodes(copyButton);
      return;
    }

    const downloadButton = event.target.closest("[data-recovery-download]");
    if (downloadButton) {
      event.preventDefault();
      downloadCodes();
      return;
    }

    const copySecretButton = event.target.closest("[data-totp-secret-copy]");
    if (copySecretButton) {
      event.preventDefault();
      copyTotpSecret(copySecretButton);
      return;
    }

    if (event.target.closest("[data-security-use-recovery]")) {
      event.preventDefault();
      setConfirmationChoice("recovery");
      recoveryInput?.focus();
      return;
    }

    if (event.target.closest("[data-security-use-totp]")) {
      event.preventDefault();
      setConfirmationChoice("totp");
      totpInput?.focus();
    }
  });

  confirmationForm?.addEventListener("submit", (event) => {
    event.preventDefault();
    if (!pendingSecurityAction || !confirmationForm.reportValidity()) return;

    pendingSecurityAction.querySelectorAll("[data-security-confirmation-value]").forEach((element) => element.remove());
    if (totpInput && !totpInput.disabled) appendSecondFactor(pendingSecurityAction, "totp_code", totpInput.value);
    if (recoveryInput && !recoveryInput.disabled) appendSecondFactor(pendingSecurityAction, "recovery_code", recoveryInput.value);

    pendingSecurityAction.dataset.securityConfirmationSubmitted = "true";
    window.bootstrap?.Modal.getInstance(confirmationModal)?.hide();
    pendingSecurityAction.requestSubmit();
  });
})();
