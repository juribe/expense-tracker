/* Dashboard onboarding banner behavior:
 * - [data-onboarding-dismiss] (the X button) hides the banner for the rest of
 *   the session only (sessionStorage): it never persists a skip. Permanent
 *   skips go through POST /onboarding/skip… (server side, see
 *   OnboardingController).
 * - [data-onboarding-later] («No ahora») postpones that step: the card hides
 *   for the rest of the session and shows a toast. Like the X close, it
 *   writes nothing to the backend — the card comes back in a new session. If
 *   every pending card is postponed, the whole banner hides. */
(function () {
  "use strict";

  var HIDDEN_KEY_PREFIX = "onboardingBannerHidden:";
  var LATER_KEY_PREFIX = "onboardingLaterSteps:";

  function storageKey(prefix, section) {
    return prefix + (section.dataset.userId || "");
  }

  function sessionFlag(section) {
    try {
      return sessionStorage.getItem(storageKey(HIDDEN_KEY_PREFIX, section));
    } catch (e) {
      return null;
    }
  }

  function hideForSession(section) {
    try {
      sessionStorage.setItem(storageKey(HIDDEN_KEY_PREFIX, section), "1");
    } catch (e) {
      /* private browsing: hiding the banner for this page view is enough */
    }
    section.hidden = true;
  }

  function laterSteps(section) {
    try {
      return JSON.parse(sessionStorage.getItem(storageKey(LATER_KEY_PREFIX, section)) || "[]");
    } catch (e) {
      return [];
    }
  }

  function storeLaterStep(section, step) {
    var steps = laterSteps(section);
    if (steps.indexOf(step) === -1) {
      try {
        sessionStorage.setItem(storageKey(LATER_KEY_PREFIX, section), JSON.stringify(steps.concat([ step ])));
      } catch (e) {
        /* private browsing: postponing only affects this page view */
      }
    }
  }

  function remainingVisibleCards(section) {
    return [...section.querySelectorAll("[data-onboarding-card]")].filter(function (card) {
      return !card.hidden;
    });
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

  function postponeCard(section, button) {
    var card = button.closest("[data-onboarding-card]");
    var step = card ? card.dataset.onboardingCard : null;
    if (step) {
      storeLaterStep(section, step);
      card.hidden = true;
    }

    if (remainingVisibleCards(section).length === 0) {
      hideForSession(section);
    }

    showToast(button.dataset.laterMessage || "");
  }

  function applyLaterSteps(section) {
    var postponed = laterSteps(section);
    if (postponed.length === 0) return;

    section.querySelectorAll("[data-onboarding-card]").forEach(function (card) {
      if (postponed.indexOf(card.dataset.onboardingCard) !== -1) card.hidden = true;
    });
    if (remainingVisibleCards(section).length === 0) section.hidden = true;
  }

  function bindLaterButtons(scope) {
    scope.querySelectorAll("[data-onboarding-later]").forEach(function (button) {
      if (button.dataset.onboardingLaterBound === "true") return;
      button.dataset.onboardingLaterBound = "true";

      button.addEventListener("click", function () { postponeCard(button.closest("[data-onboarding-banner]"), button); });
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
      applyLaterSteps(section);
      if (sessionFlag(section) === "1") section.hidden = true;
      bindBanner(section);
    });
  }

  document.addEventListener("DOMContentLoaded", function () { init(document); });
  document.addEventListener("turbo:load", function () { init(document); });
})();

