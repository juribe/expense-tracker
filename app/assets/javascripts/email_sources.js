(function () {
  function $(id) { return document.getElementById(id); }

  var SCAN_TIMEOUT_MS = 10 * 60 * 1000;
  var MAX_POLL_ERRORS = 5;
  var scanning = false;
  var detectedVerificationId = null;
  var detectedSourceId = null;
  var scanStartedAt = 0;
  var consecutiveErrors = 0;
  var timer = null;
  var toastTimer = null;

  function toast(message) {
    var el = $("toast");
    if (!el) return;
    el.textContent = message;
    el.classList.add("show");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { el.classList.remove("show"); }, 2600);
  }

  function setStep(n) {
    [1, 2, 3].forEach(function (i) {
      var el = $("step" + i);
      if (!el) return;
      el.classList.toggle("active", i === n);
      el.classList.toggle("done", i < n);
      var num = el.querySelector(".es-num");
      if (num) num.textContent = i < n ? "✓" : i;
    });
  }

  function showStatus(show) {
    var panel = $("statusPanel");
    if (panel) panel.classList.toggle("show", show);
  }

  function showSpinner(show) {
    var spinner = $("statusSpinner");
    if (spinner) spinner.style.display = show ? "block" : "none";
  }

  function setSetupInstructions(show) {
    var el = $("setupInstructions");
    if (el) el.hidden = !show;
  }

  function setNextActions(show) {
    var el = $("nextActions");
    if (el) el.hidden = !show;
  }

  function setScanControls(show) {
    var el = $("scanControls");
    if (el) el.hidden = !show;
  }

  function setLinkActionsEnabled(enabled) {
    var open = $("openLinkBtn");
    var copy = $("copyLinkBtn");
    if (open) open.disabled = !enabled;
    if (copy) copy.disabled = !enabled;
  }

  function resetLastCheck() {
    var el = $("lastCheck");
    if (el) el.textContent = "Última comprobación: —";
  }

  function setLastCheck(checkedAt) {
    var el = $("lastCheck");
    if (!el) return;
    var date = checkedAt ? new Date(checkedAt) : new Date();
    if (isNaN(date.getTime())) date = new Date();
    el.textContent = "Última comprobación: " + date.toLocaleTimeString();
  }

  function clearDetected() {
    var detected = $("detected");
    if (detected) detected.classList.remove("show");
    var sourceDetected = $("sourceDetected");
    if (sourceDetected) sourceDetected.classList.remove("show");
    detectedVerificationId = null;
    detectedSourceId = null;
  }

  function startScan() {
    scanning = true;
    scanStartedAt = Date.now();
    consecutiveErrors = 0;
    clearDetected();
    setSetupInstructions(false);
    setNextActions(false);
    setScanControls(true);
    setLinkActionsEnabled(false);
    showStatus(true);
    showSpinner(true);
    resetLastCheck();
    setStep(2);

    var title = $("statusTitle");
    if (title) title.textContent = "Buscando correo de verificación…";
    var detail = $("statusDetail");
    if (detail) detail.textContent = "Deja esta ventana abierta mientras completas la confirmación en Gmail. Revisamos automáticamente si llegó el mensaje.";

    clearInterval(timer);
    timer = setInterval(pollStatus, 3500);
    pollStatus();
    toast("Buscando correo de verificación");
  }

  function stopScan(reason) {
    scanning = false;
    clearInterval(timer);
    showSpinner(false);
    setScanControls(false);
    setNextActions(true);
    setSetupInstructions(true);

    var title = $("statusTitle");
    var detail = $("statusDetail");
    var message = "Escaneo pausado";

    if (reason === "timeout") {
      message = "La búsqueda tardó demasiado";
      if (title) title.textContent = message;
      if (detail) detail.textContent = "No recibimos el correo a tiempo. Puedes volver a comprobar cuando estés listo.";
    } else if (reason === "error") {
      message = "No pudimos comprobar el estado";
      if (title) title.textContent = message;
      if (detail) detail.textContent = "Revisa tu conexión y vuelve a intentarlo. No se modificó ninguna fuente.";
    } else {
      if (title) title.textContent = message;
      if (detail) detail.textContent = "Puedes volver a comprobar cuando hayas agregado la dirección en tu proveedor.";
    }

    toast(message);
  }

  function pollStatus() {
    if (!scanning) return;
    if (Date.now() - scanStartedAt > SCAN_TIMEOUT_MS) {
      stopScan("timeout");
      return;
    }

    fetch("/email_sources/setup_status", { headers: { "Accept": "application/json" } })
      .then(function (response) {
        if (!response.ok) throw new Error("status " + response.status);
        return response.json();
      })
      .then(function (data) {
        if (!scanning) return;
        consecutiveErrors = 0;
        setLastCheck(data.checked_at);

        if (data.verification) {
          handleVerification(data.verification);
        } else if (data.source) {
          handleSource(data.source);
        } else {
          var detail = $("statusDetail");
          if (detail) detail.textContent = "Escaneo en curso. Puedes seguir configurando Gmail en otra pestaña.";
        }
      })
      .catch(function () {
        if (!scanning) return;
        consecutiveErrors += 1;
        if (consecutiveErrors >= MAX_POLL_ERRORS) {
          stopScan("error");
          return;
        }
        var detail = $("statusDetail");
        if (detail) detail.textContent = "No se pudo comprobar ahora. Reintentando…";
      });
  }

  function handleVerification(verification) {
    scanning = false;
    clearInterval(timer);
    detectedVerificationId = verification.id;
    detectedSourceId = null;
    showSpinner(false);
    setScanControls(false);
    setSetupInstructions(false);
    setNextActions(false);

    var title = $("statusTitle");
    if (title) title.textContent = "¡Encontramos el correo de verificación!";
    var detail = $("statusDetail");
    if (detail) detail.textContent = "Detectamos un mensaje que parece corresponder a una solicitud de reenvío.";

    var email = $("detectedEmail");
    if (email) email.textContent = verification.sender || "Remitente desconocido";
    var meta = $("detectedDetail");
    if (meta) {
      meta.textContent = "Proveedor: " + (verification.provider || "Gmail") +
        " · Asunto: " + (verification.subject || "") +
        " · Recibido: " + (verification.received_at || "");
    }

    var url = verification.url || "";
    var urlEl = $("gmailLinkUrl");
    if (urlEl) {
      urlEl.textContent = url || "No pudimos validar el enlace de confirmación. Abre el correo original y revisa su contenido.";
    }
    setLinkActionsEnabled(url.length > 0);

    var detected = $("detected");
    if (detected) detected.classList.add("show");
    var sourceDetected = $("sourceDetected");
    if (sourceDetected) sourceDetected.classList.remove("show");
    toast("Correo de verificación detectado");
  }

  function handleSource(source) {
    scanning = false;
    clearInterval(timer);
    detectedSourceId = source.id;
    detectedVerificationId = null;
    showSpinner(false);
    setScanControls(false);
    setSetupInstructions(false);
    setNextActions(false);
    setLinkActionsEnabled(false);

    var title = $("statusTitle");
    if (title) title.textContent = "¡Recibimos un correo reenviado!";
    var detail = $("statusDetail");
    if (detail) detail.textContent = "Detectamos un mensaje de un remitente que aún no has aceptado.";

    var email = $("detectedSourceEmail");
    if (email) email.textContent = source.email || "";
    var meta = $("detectedSourceDetail");
    if (meta) {
      meta.textContent = "Acepta el remitente para empezar a importar sus notificaciones. Recibido: " + (source.received_at || "");
    }

    var sourceDetected = $("sourceDetected");
    if (sourceDetected) sourceDetected.classList.add("show");
    var detected = $("detected");
    if (detected) detected.classList.remove("show");
    toast("Correo reenviado detectado");
  }

  function bindCopyAddress() {
    var btn = $("copyBtn");
    if (!btn || btn.dataset.bound === "true") return;
    btn.dataset.bound = "true";
    btn.addEventListener("click", async function () {
      var value = ($("forwardAddress") || {}).textContent.trim();
      try {
        await navigator.clipboard.writeText(value);
        toast("Dirección copiada al portapapeles");
      } catch (e) {
        toast("No se pudo copiar automáticamente");
      }
    });
  }

  function bindAdd() {
    var btn = $("addBtn");
    if (!btn || btn.dataset.bound === "true") return;
    btn.dataset.bound = "true";
    btn.addEventListener("click", function () {
      var initialActions = $("initialActions");
      if (initialActions) initialActions.hidden = true;
      setSetupInstructions(true);
      setNextActions(true);
      setScanControls(false);
      showStatus(false);
      showSpinner(false);
      setStep(1);
      var instructions = $("setupInstructions");
      if (instructions) instructions.scrollIntoView({ behavior: "smooth", block: "center" });
      toast("Instrucciones listas");
    });
  }

  function bindScan() {
    var btn = $("scanBtn");
    if (!btn || btn.dataset.bound === "true") return;
    btn.dataset.bound = "true";
    btn.addEventListener("click", startScan);
  }

  function bindCheck() {
    var btn = $("checkBtn");
    if (!btn || btn.dataset.bound === "true") return;
    btn.dataset.bound = "true";
    btn.addEventListener("click", function () {
      if (scanning) pollStatus(); else startScan();
    });
  }

  function bindStop() {
    var btn = $("stopBtn");
    if (!btn || btn.dataset.bound === "true") return;
    btn.dataset.bound = "true";
    btn.addEventListener("click", function () { stopScan("user"); });
  }

  function bindRetry() {
    var btn = $("retryBtn");
    if (!btn || btn.dataset.bound === "true") return;
    btn.dataset.bound = "true";
    btn.addEventListener("click", startScan);
  }

  function bindRetrySource() {
    var btn = $("retrySourceBtn");
    if (!btn || btn.dataset.bound === "true") return;
    btn.dataset.bound = "true";
    btn.addEventListener("click", startScan);
  }

  function bindAcceptSource() {
    var btn = $("acceptSourceBtn");
    if (!btn || btn.dataset.bound === "true") return;
    btn.dataset.bound = "true";
    btn.addEventListener("click", async function () {
      if (!detectedSourceId) return;

      var original = btn.innerHTML;
      btn.disabled = true;
      btn.textContent = "Aceptando…";

      try {
        var response = await fetch("/email_sources/" + encodeURIComponent(detectedSourceId) + "/confirm", {
          method: "POST",
          headers: {
            "Accept": "application/json",
            "X-CSRF-Token": (document.querySelector('meta[name="csrf-token"]') || {}).content
          }
        });
        var json = await response.json();
        if (!response.ok || !json.ok) throw new Error("accept failed");

        scanning = false;
        clearInterval(timer);
        showSpinner(false);
        var sourceDetected = $("sourceDetected");
        if (sourceDetected) sourceDetected.classList.remove("show");
        var title = $("statusTitle");
        if (title) title.textContent = "¡Remitente aceptado!";
        var detail = $("statusDetail");
        if (detail) detail.textContent = "Ya puedes recibir notificaciones de este remitente.";
        setStep(3);
        setScanControls(false);
        setNextActions(false);
        setSetupInstructions(false);
        updateSourceRow(json.source);
        detectedSourceId = null;
        toast("Remitente aceptado");
      } catch (e) {
        toast("No se pudo aceptar el remitente");
      } finally {
        btn.disabled = false;
        btn.innerHTML = original;
      }
    });
  }

  function bindOpenLink() {
    var btn = $("openLinkBtn");
    if (!btn || btn.dataset.bound === "true") return;
    btn.dataset.bound = "true";
    btn.addEventListener("click", function () {
      if (btn.disabled) return;
      var url = ($("gmailLinkUrl") || {}).textContent.trim();
      if (!url) return;
      window.open(url, "_blank", "noopener,noreferrer");
      toast("Enlace abierto en una nueva pestaña");
    });
  }

  function bindCopyLink() {
    var btn = $("copyLinkBtn");
    if (!btn || btn.dataset.bound === "true") return;
    btn.dataset.bound = "true";
    btn.addEventListener("click", async function () {
      if (btn.disabled) return;
      var url = ($("gmailLinkUrl") || {}).textContent.trim();
      if (!url) return;
      try {
        await navigator.clipboard.writeText(url);
        toast("Enlace copiado");
      } catch (e) {
        toast("No se pudo copiar automáticamente");
      }
    });
  }

  function bindConfirm() {
    var btn = $("confirmBtn");
    if (!btn || btn.dataset.bound === "true") return;
    btn.dataset.bound = "true";
    btn.addEventListener("click", async function () {
      if (!detectedVerificationId) {
        toast("No se encontró la verificación");
        return;
      }

      var original = btn.innerHTML;
      btn.disabled = true;
      btn.textContent = "Comprobando…";

      try {
        var response = await fetch("/email_sources/verifications/" + encodeURIComponent(detectedVerificationId) + "/confirm", {
          method: "POST",
          headers: {
            "Accept": "application/json",
            "X-CSRF-Token": (document.querySelector('meta[name="csrf-token"]') || {}).content
          }
        });
        var json = await response.json();
        if (!response.ok || !json.ok) throw new Error(json.error || "confirm failed");

        scanning = false;
        clearInterval(timer);
        var detected = $("detected");
        if (detected) detected.classList.remove("show");
        showSpinner(false);
        setScanControls(false);
        setNextActions(false);
        setSetupInstructions(false);
        setStep(3);

        var title = $("statusTitle");
        if (title) title.textContent = "¡Redirección configurada!";
        var detail = $("statusDetail");
        if (detail) detail.textContent = "La fuente quedó activa y ya aparece en tus redirecciones.";
        updateSourceRow(json.source);
        detectedVerificationId = null;
        toast("Redirección activada");
      } catch (error) {
        toast("No se pudo confirmar la verificación");
      } finally {
        btn.disabled = false;
        btn.innerHTML = original;
      }
    });
  }

  function updateSourceRow(source) {
    var list = $("sourcesList");
    if (!list) return;

    var row = null;
    Array.prototype.forEach.call(list.querySelectorAll(".source-row"), function (candidate) {
      if (candidate.getAttribute("data-source-id") === String(source.id)) row = candidate;
    });

    if (!row) {
      appendSource(source);
      return;
    }

    var email = row.querySelector(".es-source-email");
    if (email) email.textContent = source.email || "Reenvío";
    var sub = row.querySelector(".es-source-sub");
    if (sub) sub.textContent = "Conectada correctamente · " + (source.received_at || new Date().toLocaleDateString());
    var pill = row.querySelector(".es-pill");
    if (pill) {
      pill.className = "es-pill es-pill-active";
      pill.innerHTML = '<span class="es-dot"></span>Activa';
    }
    var acceptForm = row.querySelector("form[data-accept-form]");
    if (acceptForm) acceptForm.remove();
    updateSourceCount();
  }

  function updateSourceCount() {
    var list = $("sourcesList");
    var count = $("sourceCount");
    if (!list || !count) return;
    var n = list.querySelectorAll(".es-pill-active").length;
    count.innerHTML = '<span class="es-dot"></span>' + n + ' ' + (n === 1 ? "activa" : "activas");
  }

  function appendSource(source) {
    var list = $("sourcesList");
    if (!list) return;
    var empty = $("emptySources");
    if (empty) empty.remove();

    var row = document.createElement("div");
    row.className = "es-source-row source-row";
    row.setAttribute("data-source-id", source.id);

    var statusLabel = source.status === "active" ? "Activa" : "Pendiente";
    var statusClass = source.status === "active" ? "es-pill-active" : "es-pill-pending";
    var sub = source.status === "active" ? "Conectada correctamente" : "Esperando confirmación";
    var date = source.received_at || new Date().toLocaleDateString();
    var csrf = (document.querySelector('meta[name="csrf-token"]') || {}).content || "";
    var deleteConfirm = (document.querySelector(".email-sources-page") || {}).dataset.deleteConfirm || "";

    row.innerHTML =
      '<div class="es-gmail-icon">@</div>' +
      '<div class="es-source-main">' +
        '<div class="es-source-email">' + escapeHtml(source.email || "Reenvío") + '</div>' +
        '<div class="es-source-sub">' + sub + ' · ' + date + '</div>' +
      '</div>' +
      '<span class="es-pill ' + statusClass + '"><span class="es-dot"></span>' + statusLabel + '</span>' +
      '<form class="es-delete-form" action="/email_sources/' + encodeURIComponent(source.id) + '" method="post" data-turbo-confirm="' + escapeHtml(deleteConfirm) + '">' +
        '<input type="hidden" name="_method" value="delete">' +
        '<input type="hidden" name="authenticity_token" value="' + escapeHtml(csrf) + '">' +
        '<button class="es-btn es-btn-danger es-btn-sm" type="submit">Eliminar</button>' +
      '</form>';

    list.appendChild(row);
    updateSourceCount();
  }

  function escapeHtml(str) {
    return String(str).replace(/[&<>"']/g, function (m) {
      return ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[m];
    });
  }

  function init() {
    bindCopyAddress();
    bindAdd();
    bindScan();
    bindCheck();
    bindStop();
    bindRetry();
    bindRetrySource();
    bindAcceptSource();
    bindOpenLink();
    bindCopyLink();
    bindConfirm();
  }

  document.addEventListener("DOMContentLoaded", init);
  document.addEventListener("turbo:load", init);
})();
