// Money tracking mode picker: keeps the visual selection, the status copy and
// the submit button in sync. The form itself stays a normal PATCH to the
// existing endpoint, so confirmation/eligibility rules are unchanged.
(function () {
  var LABELS = {
    simple: {
      current: "Tu modalidad actual es Seguimiento simple.",
      next: "Vas a cambiar a Seguimiento simple."
    },
    detailed: {
      current: "Tu modalidad actual es Seguimiento completo.",
      next: "Vas a cambiar a Seguimiento completo."
    }
  };

  function bind() {
    var form = document.querySelector("[data-money-tracking-form]");
    if (!form || form.dataset.moneyTrackingBound === "true") return;
    form.dataset.moneyTrackingBound = "true";

    var options = Array.prototype.slice.call(form.querySelectorAll(".mt-option[data-mode]"));
    var button = form.querySelector("[data-testid='money-tracking-submit']");
    var status = document.querySelector("[data-money-tracking-status]");
    var current = form.getAttribute("data-current-mode") || "simple";
    var selected = current;

    function render() {
      options.forEach(function (option) {
        option.classList.toggle("is-selected", option.getAttribute("data-mode") === selected);
      });

      if (button) button.disabled = selected === current;

      if (status) {
        var copy = LABELS[selected] || LABELS[current];
        status.textContent = selected === current ? copy.current : copy.next;
      }
    }

    form.addEventListener("change", function (event) {
      var input = event.target;
      if (!input || input.name !== "money_tracking_mode") return;

      selected = input.value;
      render();
    });

    var checked = form.querySelector("input[name='money_tracking_mode']:checked");
    if (checked) selected = checked.value;

    render();
  }

  document.addEventListener("DOMContentLoaded", bind);
  document.addEventListener("turbo:load", bind);
  if (document.readyState !== "loading") bind();
})();
