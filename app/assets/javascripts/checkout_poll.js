// Polls the checkout status endpoint so the result page can react to the
// webhook confirmation without requiring a manual refresh.
(function () {
  document.addEventListener("DOMContentLoaded", function () {
    var root = document.querySelector("[data-checkout-status-url]");
    if (!root) return;

    var url = root.dataset.checkoutStatusUrl;
    var ref = root.dataset.checkoutRefPayco;
    var successUrl = root.dataset.checkoutSuccessUrl || "/";
    var statusEl = document.querySelector("[data-checkout-status]");
    var headingEl = document.querySelector("[data-checkout-heading]");
    var messageEl = document.querySelector("[data-checkout-message]");
    var eyebrowEl = document.querySelector("[data-checkout-eyebrow]");
    var copyBtn = document.querySelector("[data-copy-reference]");
    var intervals = [5000, 10000, 15000, 20000, 25000, 30000];
    var attempt = 0;
    var timer = null;
    var stopped = false;

    var labels = {
      pending: "Pendiente",
      succeeded: "Aprobado",
      failed: "No completado",
      refunded: "Reembolsado"
    };

    if (copyBtn) {
      copyBtn.addEventListener("click", function () {
        var refId = copyBtn.dataset.copyReference;
        var refEl = document.getElementById(refId);
        if (!refEl) return;
        var text = refEl.textContent;
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(text).then(function () {
            copyBtn.textContent = "¡Copiada!";
          }).catch(function () {
            copyBtn.textContent = "Selecciona la referencia";
          });
        } else {
          copyBtn.textContent = "Selecciona la referencia";
        }
      });
    }

    function applyStatus(status) {
      if (statusEl) statusEl.textContent = labels[status] || status;

      if (status === "succeeded") {
        if (eyebrowEl) eyebrowEl.innerHTML = "<span>✓</span> Pago aprobado";
        if (headingEl) headingEl.textContent = "¡Tu pago fue aprobado!";
        if (messageEl) messageEl.textContent = "Tu membresía se activó correctamente. Te llevaremos a tu dashboard en unos segundos.";
      } else if (status === "failed" || status === "refunded") {
        if (eyebrowEl) eyebrowEl.innerHTML = "<span>!</span> Pago no completado";
        if (headingEl) headingEl.textContent = "No pudimos completar tu pago";
        if (messageEl) messageEl.textContent = "ePayco canceló o rechazó la transacción. No se realizó ningún cobro; puedes intentarlo nuevamente desde tus planes.";
      }
    }

    function stop() {
      stopped = true;
      if (timer) {
        clearTimeout(timer);
        timer = null;
      }
    }

    function schedule() {
      if (stopped) return;
      var delay = intervals[Math.min(attempt, intervals.length - 1)];
      timer = setTimeout(poll, delay);
      attempt += 1;
    }

    function poll() {
      var fetchUrl = url + (ref ? "?ref_payco=" + encodeURIComponent(ref) : "");
      fetch(fetchUrl, { headers: { "Accept": "application/json" } })
        .then(function (res) { return res.json(); })
        .then(function (data) {
          applyStatus(data.status);

          if (data.status === "succeeded" || data.status === "failed" || data.status === "refunded") {
            stop();
            if (data.status === "succeeded") {
              setTimeout(function () { window.location.href = successUrl; }, 3000);
            }
            return;
          }

          schedule();
        })
        .catch(function () { schedule(); });
    }

    if (statusEl) applyStatus(statusEl.textContent.trim());
    poll();
  });
})();
