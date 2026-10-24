/* Dashboard onboarding banner behavior:
 * - [data-onboarding-dismiss] (the X button) hides the banner for the rest of
 *   the session only (sessionStorage): it never persists a skip. Permanent
 *   skips go through POST /onboarding/skip… (server side, see
 *   OnboardingController).
 * - [data-onboarding-later] («No ahora») shows a toast; it does not change
 *   any step state either — the card stays until the user acts on it. */
(function () {
  "use strict";

  var STORAGE_PREFIX = "onboardingBannerHidden:";

  function storageKey(section) {
    return STORAGE_PREFIX + (section.dataset.userId || "");
  }

  function sessionFlag(section) {
    try {
      return sessionStorage.getItem(storageKey(section));
    } catch (e) {
      return null;
    }
  }

  function hideForSession(section) {
    try {
      sessionStorage.setItem(storageKey(section), "1");
    } catch (e) {
      /* private browsing: hiding the banner for this page view is enough */
    }
    section.hidden = true;
  }

  function showToast(message) {
    if (!window.bootstrap || typeof window.bootstrap.Toast !== "function") return;

    var toast = document.createElement("div");
    toast.className = "toast align-items-center text-bg-light border m-3 position-fixed bottom-0 end-0";
    toast.setAttribute("role", "status");
    toast.setAttribute("aria-live", "polite");
    toast.innerHTML =
      '<div class="d-flex">' +
      '<div class="toast-body">' + message + "</div>" +
      '<button type="button" class="btn-close me-2 m-auto" data-bs-dismiss="toast" aria-label="Cerrar"></button>' +
      "</div>";
    document.body.appendChild(toast);

    var instance = new window.bootstrap.Toast(toast, { delay: 3000, autohide: true });
    toast.addEventListener("hidden.bs.toast", function () { toast.remove(); });
    instance.show();
  }

  function bindLaterButtons(scope) {
    scope.querySelectorAll("[data-onboarding-later]").forEach(function (button) {
      if (button.dataset.onboardingLaterBound === "true") return;
      button.dataset.onboardingLaterBound = "true";

      button.addEventListener("click", function () {
        showToast(button.dataset.laterMessage || "");
      });
    });
  }

  function bindBanner(section) {
    if (section.dataset.onboardingBound === "true") return;
    section.dataset.onboardingBound = "true";

    var dismiss = section.querySelector("[data-onboarding-dismiss]");
    if (dismiss) {
      dismiss.addEventListener("click", function () { hideForSession(section); });
    }
    bindLaterButtons(section);
  }

  function init(root) {
    var scope = root || document;
    scope.querySelectorAll("[data-onboarding-banner]").forEach(function (section) {
      if (sessionFlag(section) === "1") section.hidden = true;
      bindBanner(section);
    });
  }

  document.addEventListener("DOMContentLoaded", function () { init(document); });
  document.addEventListener("turbo:load", function () { init(document); });
})();
