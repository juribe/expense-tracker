// Payments
// Live "payment distribution" checker for the apply-payment form. Keeps the
// entered components' total visible and only enables submit when the total
// matches the expense amount bound to the form.
//
// Example: form[data-payment-distribution-form="true"] with component inputs
// [data-payment-component="true"] and [data-payment-expense-total="1500000"].
(function () {
  var FORM_SELECTOR = '[data-payment-distribution-form="true"]';
  var PLACEHOLDERS = { short: "__MISSING__", over: "__EXTRA__" };

  function toNumber(value) {
    var parsed = parseFloat(String(value == null ? "" : value).replace(/[^0-9.]/g, ""));
    return isNaN(parsed) ? 0 : parsed;
  }

  function componentValue(input) {
    var raw = window.MoneyInputs ? window.MoneyInputs.sanitizeValue(input.value) : input.value;
    return toNumber(raw);
  }

  // es-CO: "." thousands.
  function formatMoney(value) {
    return Math.round(Math.abs(value)).toLocaleString("es-CO");
  }

  function bindForm(form) {
    if (form.dataset.paymentDistributionBound === "true") return;
    form.dataset.paymentDistributionBound = "true";

    var totalSource = form.querySelector("[data-payment-expense-total]");
    var display = form.querySelector("[data-payment-total-display]");
    var warning = form.querySelector("[data-payment-warning]");
    var warningText = form.querySelector("[data-payment-warning-text]");
    var submit = form.querySelector("button[type='submit'], input[type='submit']");
    var inputs = Array.prototype.slice.call(form.querySelectorAll("[data-payment-component='true']"));
    if (!totalSource || !display || inputs.length === 0) return;

    var expected = parseFloat(totalSource.dataset.paymentExpenseTotal) || 0;

    function update() {
      var total = inputs.reduce(function (sum, input) { return sum + componentValue(input); }, 0);
      var diff = total - expected;

      display.textContent = "$" + formatMoney(total);

      var message = null;
      if (total === 0) {
        message = totalSource.dataset.paymentWarningEmpty;
      } else if (diff < 0) {
        message = totalSource.dataset.paymentWarningShort.replace(PLACEHOLDERS.short, formatMoney(diff));
      } else if (diff > 0) {
        message = totalSource.dataset.paymentWarningOver.replace(PLACEHOLDERS.over, formatMoney(diff));
      }

      if (message) {
        warningText.textContent = message;
        warning.classList.remove("d-none");
        if (submit) submit.disabled = true;
      } else {
        warning.classList.add("d-none");
        if (submit) submit.disabled = false;
      }

      var amountInput = form.querySelector("[data-payment-amount]");
      if (amountInput) amountInput.value = total > 0 ? String(total) : "";
    }

    inputs.forEach(function (input) {
      input.addEventListener("input", update);
      input.addEventListener("blur", update);
    });
    update();
  }

  function init(root) {
    var scope = root || document;
    Array.prototype.slice.call(scope.querySelectorAll(FORM_SELECTOR)).forEach(bindForm);
  }

  window.PaymentDistribution = { init: init };

  document.addEventListener("DOMContentLoaded", function () { init(document); });
  document.addEventListener("turbo:load", function () { init(document); });
})();
