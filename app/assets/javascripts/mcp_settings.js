(function () {
  var RESET_MS = 1800;

  function fallbackCopy(value) {
    var field = document.createElement("textarea");
    field.value = value;
    field.setAttribute("readonly", "");
    field.style.position = "fixed";
    field.style.opacity = "0";
    document.body.appendChild(field);
    field.select();

    var copied = document.execCommand("copy");
    document.body.removeChild(field);
    return copied;
  }

  function copyValue(value) {
    if (navigator.clipboard && window.isSecureContext) {
      return navigator.clipboard.writeText(value).then(
        function () { return true; },
        function () { return fallbackCopy(value); }
      );
    }

    return Promise.resolve(fallbackCopy(value));
  }

  function showResult(button, label) {
    var target = button.querySelector("[data-copy-label]");
    if (target) target.textContent = label;
    button.classList.toggle("is-copied", label === button.dataset.copiedLabel);
  }

  function reset(button) {
    var target = button.querySelector("[data-copy-label]");
    if (target) target.textContent = button.dataset.originalLabel || "";
    button.classList.remove("is-copied");
  }

  function showToast(message) {
    var toast = document.getElementById("mcp-copy-toast");
    if (!toast) {
      toast = document.createElement("div");
      toast.id = "mcp-copy-toast";
      toast.className = "mcp-copy-toast";
      document.body.appendChild(toast);
    }
    toast.textContent = message;
    toast.classList.add("is-visible");
    window.clearTimeout(toast._timer);
    toast._timer = window.setTimeout(function () {
      toast.classList.remove("is-visible");
    }, 1800);
  }

  function keybox() {
    return document.querySelector(".mcp-keybox");
  }

  function keyValue() {
    var box = keybox();
    return box ? (box.getAttribute("data-key") || "") : "";
  }

  function endpointValue() {
    var field = document.querySelector("[data-testid='mcp-endpoint'] code");
    return field ? field.textContent.trim() : "";
  }

  function updateKeyDisplay(revealed) {
    var value = keyValue();
    var code = document.getElementById("keyValue");
    if (!code) return;
    if (!value) {
      code.textContent = "••••••••••••••••••••••••";
      return;
    }
    code.textContent = revealed ? value : "•".repeat(26);
    var btn = document.getElementById("reveal");
    if (btn) btn.textContent = revealed ? (btn.dataset.hideLabel || "Ocultar") : (btn.dataset.revealLabel || "Mostrar");
  }

  function toggleReveal() {
    var btn = document.getElementById("reveal");
    if (!btn || btn.disabled) return;
    var revealed = btn.dataset.revealed !== "true";
    btn.dataset.revealed = revealed ? "true" : "false";
    updateKeyDisplay(revealed);
  }

  function copyKey() {
    var value = keyValue();
    if (!value) return;
    copyValue(value).then(function (copied) {
      showToast(copied ? (document.getElementById("copyKey").dataset.copiedLabel || "Copiado") : (document.getElementById("copyKey").dataset.copyFailedLabel || "No se pudo copiar"));
    });
  }

  function copyPrompt() {
    var target = document.getElementById("prompt");
    var value = target ? (target.innerText || target.textContent || "") : "";
    if (!value || value.indexOf("Crea primero") === 0) return;
    var btn = document.getElementById("copyPrompt");
    copyValue(value).then(function (copied) {
      var label = copied ? (btn.dataset.copiedLabel || "Copiado") : (btn.dataset.copyFailedLabel || "No se pudo copiar");
      if (btn.querySelector("[data-copy-label]")) btn.querySelector("[data-copy-label]").textContent = label;
      btn.classList.toggle("is-copied", copied);
      showToast(label);
      window.setTimeout(function () {
        if (btn.querySelector("[data-copy-label]")) btn.querySelector("[data-copy-label]").textContent = btn.dataset.originalLabel || "";
        btn.classList.remove("is-copied");
      }, RESET_MS);
    });
  }

  function info(event) {
    if (event) event.preventDefault();
    showToast("Usa la misma dirección y clave en tu asistente compatible.");
  }

  document.addEventListener("click", function (event) {
    var copyBtn = event.target.closest("[data-copy-value], [data-copy-target]");
    if (copyBtn) {
      event.preventDefault();

      if (!copyBtn.dataset.originalLabel) {
        var label = copyBtn.querySelector("[data-copy-label]");
        copyBtn.dataset.originalLabel = label ? label.textContent : "";
      }

      var value = copyBtn.getAttribute("data-copy-value");
      var targetId = copyBtn.getAttribute("data-copy-target");
      if (targetId) {
        var target = document.getElementById(targetId);
        if (target) value = target.innerText || target.textContent || "";
      }
      if (!value || value.indexOf("Crea primero") === 0) return;

      copyValue(value).then(function (copied) {
        var label = copied ? copyBtn.dataset.copiedLabel : copyBtn.dataset.copyFailedLabel;
        showResult(copyBtn, label);
        showToast(label);
        window.setTimeout(function () { reset(copyBtn); }, RESET_MS);
      });
      return;
    }

    var actionBtn = event.target.closest("[data-action]");
    if (actionBtn) {
      var action = actionBtn.getAttribute("data-action");
      if (action === "reveal") { toggleReveal(); return; }
      if (action === "copy-key") { copyKey(); return; }
      if (action === "copy-prompt") { copyPrompt(); return; }
      if (action === "info") { info(event); return; }
    }

    var infoLink = event.target.closest("[data-info]");
    if (infoLink) {
      info(event);
    }
  });

  // Initialize reveal label data attributes.
  document.addEventListener("DOMContentLoaded", function () {
    var copyKeyBtn = document.getElementById("copyKey");
    if (copyKeyBtn) {
      copyKeyBtn.dataset.copiedLabel = (copyKeyBtn.getAttribute("data-copied-label") || "Copiado");
      copyKeyBtn.dataset.copyFailedLabel = (copyKeyBtn.getAttribute("data-copy-failed-label") || "No se pudo copiar");
    }
  });

  document.addEventListener("turbo:load", function () { });
})();
