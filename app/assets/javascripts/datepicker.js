// Spanish date pickers (Flatpickr, vendored under app/assets/vendor/flatpickr).
//
// Native <input type="date"> renders its calendar widget in the browser
// language, not the application language, so every date input is upgraded to
// a Flatpickr calendar with the Spanish locale and the es-CO display format
// dd/MM/yyyy (altFormat). The hidden original input keeps name + ISO value
// (Y-m-d), exactly what the controllers already parse.
(function () {
  var identityAttrs = ["data-testid", "aria-label", "aria-invalid", "aria-describedby", "autofocus"];

  function spanishLocale() {
    var pack = window.es;
    if (pack && pack.Spanish) return pack.Spanish;
    return "es";
  }

  // Users type into the visible input; tests and labels target it. Flatpickr
  // copies classes/placeholder/disabled/required itself, but leaves id and
  // data attributes on the hidden original — move the identity over.
  function handOffIdentity(_selectedDates, _dateStr, fp) {
    var alt = fp.altInput;
    var input = fp.input;
    identityAttrs.forEach(function (attr) {      var value = input.getAttribute(attr);
      if (value !== null) {
        alt.setAttribute(attr, value);
        input.removeAttribute(attr);
      }
    });
    if (input.id) {
      alt.id = input.id;
      input.removeAttribute("id");
    }
  }

  function pick(input) {
    if (input.type !== "date" || input.dataset.datepickerBound === "true") return;
    input.dataset.datepickerBound = "true";

    flatpickr(input, {
      locale: spanishLocale(),
      dateFormat: "Y-m-d",
      altInput: true,
      altFormat: "d/m/Y",
      disableMobile: true,
      allowInput: true,
      onReady: handOffIdentity
    });
  }

  function bind(scope) {
    if (!window.flatpickr) return;
    (scope || document).querySelectorAll('input[type="date"]').forEach(pick);
  }

  // Inputs re-rendered on the client (drawers, injected forms) are never
  // covered by turbo:load; upgrading them on focus keeps every form covered.
  document.addEventListener("focusin", function (e) {
    if (e.target && e.target.type === "date") pick(e.target);
  });

  document.addEventListener("DOMContentLoaded", function () { bind(document); });
  document.addEventListener("turbo:load", function () { bind(document); });
})();
