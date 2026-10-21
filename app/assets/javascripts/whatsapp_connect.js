// Settings → WhatsApp connection flow. Clicking the primary CONNECT token
// button opens WhatsApp and switches the section to a "Connecting…" state.
// The status endpoint is polled every 30 seconds for up to 3 minutes (6
// attempts, never more frequently); a single timer is guaranteed and cleaned
// up on cancel, on navigation and as soon as the backend reports connected.
(function () {
  var POLL_INTERVAL_MS = 30000;
  var MAX_ATTEMPTS = 6;
  var MAX_DURATION_MS = 3 * 60 * 1000;
  var timer = null;
  var attemptsLeft = 0;

  // Rails rejects state-changing fetches without the CSRF token header.
  function csrfToken() {
    var meta = document.querySelector('meta[name="csrf-token"]');
    return meta ? meta.content : "";
  }

  function fetchWithCsrf(url, options) {
    return fetch(url, Object.assign({}, options, {
      credentials: "same-origin",
      headers: Object.assign({ "X-CSRF-Token": csrfToken() }, options.headers)
    }));
  }

  function connectCard() {
    return document.getElementById("whatsapp-connect-card");
  }

  function stopTimer() {
    if (timer) {
      clearInterval(timer);
      timer = null;
    }
    attemptsLeft = 0;
  }

  function setState(name) {
    var root = connectCard();
    if (!root) return;
    root.querySelectorAll("[data-connect-state]").forEach(function (el) {
      el.hidden = el.getAttribute("data-connect-state") !== name;
    });
  }

  function reloadSection(url) {
    if (window.Turbo) {
      Turbo.visit(url);
    } else {
      window.location.replace(url);
    }
  }

  function finishExpired() {
    stopTimer();
    var root = connectCard();
    if (!root) return;
    fetchWithCsrf(root.dataset.cancelUrl, { method: "DELETE" })
      .then(function () { reloadSection(root.dataset.expiredUrl); })
      .catch(function () { reloadSection(root.dataset.expiredUrl); });
  }

  function pollStatus() {
    var root = connectCard();
    if (!root) return;
    fetch(root.dataset.statusUrl, { headers: { Accept: "application/json" }, credentials: "same-origin" })
      .then(function (response) { return response.json(); })
      .then(function (data) {
        if (data.status === "connected") {
          stopTimer();
          reloadSection(window.location.href);
        } else if (data.status !== "pending") {
          finishExpired();
        }
      })
      .catch(function () { /* transient network error: keep waiting */ });
  }

  function startPolling() {
    var root = connectCard();
    if (!root) return;
    stopTimer();
    attemptsLeft = MAX_ATTEMPTS;
    var deadline = Date.now() + MAX_DURATION_MS;
    timer = setInterval(function () {
      attemptsLeft -= 1;
      if (attemptsLeft <= 0 || Date.now() >= deadline) {
        finishExpired();
        return;
      }
      pollStatus();
    }, POLL_INTERVAL_MS);
  }

  function bindCard() {
    var root = connectCard();
    if (!root || root.dataset.bound) return;
    root.dataset.bound = "1";

    var tokenButton = root.querySelector("[data-connect-action]");
    if (tokenButton) {
      tokenButton.addEventListener("click", function () {
        // Expose the same deep link in the connecting state before switching.
        var reopen = root.querySelector("[data-reopen-link]");
        if (reopen) {
          reopen.href = tokenButton.href;
          reopen.classList.remove("d-none");
        }
        setState("connecting");
        startPolling();
      });
    }

    var cancelButton = root.querySelector("[data-cancel-action]");
    if (cancelButton) {
      cancelButton.addEventListener("click", function () {
        stopTimer();
        fetchWithCsrf(root.dataset.cancelUrl, { method: "DELETE" })
          .then(function () { reloadSection(root.dataset.cleanUrl); })
          .catch(function () { reloadSection(root.dataset.cleanUrl); });
      });
    }
  }

  stopTimer();
  document.addEventListener("turbo:load", bindCard);
  document.addEventListener("turbo:before-render", stopTimer);
  document.addEventListener("turbo:visit", stopTimer);
  if (document.readyState !== "loading") {
    bindCard();
  } else {
    document.addEventListener("DOMContentLoaded", bindCard);
  }
})();
