// Polls the checkout status endpoint so the result page can react to the
// webhook confirmation without requiring a manual refresh.
(function () {
  document.addEventListener("DOMContentLoaded", function () {
    var root = document.querySelector("[data-checkout-status-url]");
    if (!root) return;

    var url = root.dataset.checkoutStatusUrl;
    var ref = root.dataset.checkoutRefPayco;
    var statusEl = document.querySelector("[data-checkout-status]");
    var interval = null;

    function poll() {
      var fetchUrl = url + (ref ? "?ref_payco=" + encodeURIComponent(ref) : "");
      fetch(fetchUrl, { headers: { "Accept": "application/json" } })
        .then(function (res) { return res.json(); })
        .then(function (data) {
          if (statusEl) statusEl.textContent = data.status;
          if (data.status === "succeeded" || data.status === "failed" || data.status === "refunded") {
            if (interval) clearInterval(interval);
            if (data.status === "succeeded") {
              setTimeout(function () { window.location.href = "/plans"; }, 3000);
            }
          }
        })
        .catch(function () {});
    }

    poll();
    interval = setInterval(poll, 3000);
  });
})();