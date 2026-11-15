/* Service worker registration and update prompts.
 * New versions are announced instead of activated silently: the page reloads
 * only after the user accepts the update. */
(function () {
  "use strict";

  var registration = null;
  var reloadRequested = false;

  function updateBanner() {
    return document.querySelector("[data-pwa-update]");
  }

  function showUpdate(reg) {
    if (reg) registration = reg;
    var banner = updateBanner();
    if (banner) banner.hidden = false;
  }

  function hideUpdate() {
    var banner = updateBanner();
    if (banner) banner.hidden = true;
  }

  function acceptUpdate() {
    var waiting = registration && registration.waiting;
    hideUpdate();
    if (!waiting) {
      window.location.reload();
      return;
    }
    reloadRequested = true;
    waiting.postMessage({ type: "SKIP_WAITING" });
  }

  function watchRegistration(reg) {
    registration = reg;
    if (reg.waiting && navigator.serviceWorker.controller) showUpdate(reg);

    reg.addEventListener("updatefound", function () {
      var worker = reg.installing;
      if (!worker) return;
      worker.addEventListener("statechange", function () {
        if (worker.state === "installed" && navigator.serviceWorker.controller) {
          showUpdate(reg);
        }
      });
    });
  }

  function checkForUpdate() {
    if (!registration || registration.waiting) return;
    registration.update().catch(function () { /* offline or throttled */ });
  }

  function wirePrompts() {
    document.addEventListener("click", function (event) {
      if (event.target.closest("[data-pwa-update-accept]")) {
        acceptUpdate();
        return;
      }
      if (event.target.closest("[data-pwa-update-dismiss]")) {
        hideUpdate();
      }
    });
  }

  function start() {
    if (!("serviceWorker" in navigator)) return;

    wirePrompts();
    navigator.serviceWorker.addEventListener("controllerchange", function () {
      if (reloadRequested) window.location.reload();
    });

    navigator.serviceWorker
      .register("/service-worker", { scope: "/", updateViaCache: "none" })
      .then(watchRegistration)
      .catch(function () { /* registration is optional */ });

    document.addEventListener("visibilitychange", function () {
      if (document.visibilityState === "visible") checkForUpdate();
    });
    window.setInterval(checkForUpdate, 60 * 60 * 1000);
  }

  start();
})();
