// Polls the checkout status endpoint so the result page can react to the
// webhook confirmation without requiring a manual refresh.
(function () {
  document.addEventListener("DOMContentLoaded", function () {
    var root = document.querySelector("[data-checkout-status-url]");
    if (!root) return;

    var url = root.dataset.checkoutStatusUrl;
    var ref = root.dataset.checkoutRefPayco;
    var statusEl = document.querySelector("[data-checkout-status]");
    var copyBtn = document.querySelector("[data-copy-reference]");
    var intervals = [5000, 10000, 15000, 20000, 25000, 30000];
    var attempt = 0;
    var timer = null;
    var stopped = false;

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
          if (statusEl) statusEl.textContent = data.status;

          if (data.status === "succeeded" || data.status === "failed" || data.status === "refunded") {
            stop();
            if (data.status === "succeeded") {
              setTimeout(function () { window.location.href = "/plans"; }, 3000);
            }
            return;
          }

          schedule();
        })
        .catch(function () { schedule(); });
    }

    poll();
  });
})();
