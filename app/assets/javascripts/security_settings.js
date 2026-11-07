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
    }
  });
})();
