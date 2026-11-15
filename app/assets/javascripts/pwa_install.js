/* Install entry points.
 * Shows "Instalar Yogasto" when the browser allows it and falls back to
 * Safari's Share -> Add to Home Screen instructions on iOS, where the
 * beforeinstallprompt event does not exist. */
(function () {
  "use strict";

  var DISMISS_KEY = "etPwaInstallDismissedAt";
  var INSTALLED_KEY = "etPwaInstalled";
  var DISMISS_DAYS = 30;
  var BANNER_DELAY = 3000;

  var deferredPrompt = null;
  var installed = false;

  function isStandalone() {
    var media = window.matchMedia && window.matchMedia("(display-mode: standalone)").matches;
    return media || window.navigator.standalone === true;
  }

  function isIos() {
    var ua = navigator.userAgent || "";
    if (/iPad|iPhone|iPod/.test(ua)) return true;
    return navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1;
  }

  function banner() {
    return document.querySelector("[data-pwa-install-banner]");
  }

  function entryPoints() {
    return document.querySelectorAll("[data-pwa-install-menu], [data-pwa-install-settings]");
  }

  function dismissedRecently() {
    try {
      var at = parseInt(localStorage.getItem(DISMISS_KEY), 10);
      return !!at && Date.now() - at < DISMISS_DAYS * 24 * 60 * 60 * 1000;
    } catch (error) {
      return false;
    }
  }

  function rememberDismissal() {
    try {
      localStorage.setItem(DISMISS_KEY, String(Date.now()));
    } catch (error) { /* storage unavailable */ }
  }

  function rememberInstalled() {
    try {
      localStorage.setItem(INSTALLED_KEY, "1");
    } catch (error) { /* storage unavailable */ }
  }

  function knownInstalled() {
    try {
      return localStorage.getItem(INSTALLED_KEY) === "1";
    } catch (error) {
      return false;
    }
  }

  function available() {
    return !installed && !isStandalone();
  }

  function showEntryPoints() {
    if (!available()) return;
    entryPoints().forEach(function (element) { element.hidden = false; });
  }

  function showBanner() {
    if (!available() || dismissedRecently()) return;
    var element = banner();
    if (element) element.hidden = false;
  }

  function hideInstallUi() {
    entryPoints().forEach(function (element) { element.hidden = true; });
    var element = banner();
    if (element) element.hidden = true;
  }

  function dismissBanner() {
    rememberDismissal();
    var element = banner();
    if (element) element.hidden = true;
  }

  function dialog() {
    return document.querySelector("[data-pwa-ios-dialog]");
  }

  function openIosDialog() {
    var element = dialog();
    if (!element) return;
    if (typeof element.showModal === "function") {
      element.showModal();
    } else {
      element.setAttribute("open", "");
    }
  }

  function closeIosDialog() {
    var element = dialog();
    if (!element) return;
    if (typeof element.close === "function") {
      element.close();
    } else {
      element.removeAttribute("open");
    }
  }

  function promptInstall() {
    if (!deferredPrompt) {
      if (isIos()) openIosDialog();
      return;
    }

    var promptEvent = deferredPrompt;
    deferredPrompt = null;
    promptEvent.prompt();
    promptEvent.userChoice
      .then(function (choice) {
        if (choice && choice.outcome === "accepted") {
          hideInstallUi();
        } else {
          dismissBanner();
        }
      })
      .catch(function () { /* the browser dismissed the prompt */ });
  }

  function onBeforeInstallPrompt(event) {
    event.preventDefault();
    deferredPrompt = event;
    // A prompt means the browser considers it installable right now.
    installed = false;
    showEntryPoints();
    showBanner();
  }

  function onInstalled() {
    installed = true;
    deferredPrompt = null;
    rememberInstalled();
    hideInstallUi();
  }

  function wireEvents() {
    if (document.documentElement.dataset.pwaInstallWired) return;
    document.documentElement.dataset.pwaInstallWired = "1";

    window.addEventListener("beforeinstallprompt", onBeforeInstallPrompt);
    window.addEventListener("appinstalled", onInstalled);

    document.addEventListener("click", function (event) {
      if (event.target.closest("[data-pwa-install-trigger]")) {
        event.preventDefault();
        promptInstall();
        return;
      }
      if (event.target.closest("[data-pwa-install-dismiss]")) {
        dismissBanner();
        return;
      }
      if (event.target.closest("[data-pwa-dialog-close]")) {
        closeIosDialog();
      }
    });

    var element = dialog();
    if (element) {
      element.addEventListener("click", function (event) {
        if (event.target === element) closeIosDialog();
      });
    }

    if (window.matchMedia) {
      window.matchMedia("(display-mode: standalone)").addEventListener("change", function (event) {
        if (event.matches) {
          installed = true;
          rememberInstalled();
          hideInstallUi();
        }
      });
    }
  }

  function start() {
    if (isStandalone()) {
      installed = true;
      rememberInstalled();
      return;
    }

    installed = knownInstalled();
    wireEvents();

    if (!installed && isIos()) {
      showEntryPoints();
      window.setTimeout(showBanner, BANNER_DELAY);
    }
  }

  start();
})();
