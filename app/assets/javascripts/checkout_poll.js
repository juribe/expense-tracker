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
    var intervals = [5000, 10000, 15000, 20000, 25000, 30000];
    var intervalIndex = 0;

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

    function scheduleNext() {
      if (interval) clearInterval(interval);
      interval = setInterval(function () {
        poll();
        intervalIndex = Math.min(intervalIndex + 1, intervals.length - 1);
        scheduleNext();
      }, intervals[intervalIndex]);
    }

    poll();
    scheduleNext();
  });
})();