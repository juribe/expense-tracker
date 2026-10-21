// Payments
// Live "payment distribution" checker for the apply-payment form. Keeps the
// entered components' total visible and only enables submit when the total
// matches the expense amount bound to the form.
//
// Example: form[data-payment-distribution-form="true"] with component inputs
// [data-payment-component="true"] and [data-payment-expense-total="1500000"].
(function () {
  var FORM_SELECTOR = '[data-payment-distribution-form="true"]';
  var MANUAL_FORM_SELECTOR = '[data-manual-payment-form="true"]';
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

  function csrfToken() {
    var meta = document.querySelector("meta[name='csrf-token']");
    return meta ? meta.getAttribute("content") : "";
  }

  // Live "payment distribution" checker. The expected total is either a static
  // amount (data-payment-expense-total, the "apply to an existing expense"
  // form) or a typed target input (data-payment-target-input, the manual
  // payment form where the user enters the amount).
  function bindForm(form) {
    if (form.dataset.paymentDistributionBound === "true") return;
    form.dataset.paymentDistributionBound = "true";

    var totalSource = form.querySelector("[data-payment-expense-total]");
    var targetInput = form.querySelector("[data-payment-target-input]");
    var display = form.querySelector("[data-payment-total-display]");
    var warning = form.querySelector("[data-payment-warning]");
    var warningText = form.querySelector("[data-payment-warning-text]");
    var submit = form.querySelector("button[type='submit'], input[type='submit']");
    var inputs = Array.prototype.slice.call(form.querySelectorAll("[data-payment-component='true']"));
    if (!display || inputs.length === 0 || (!totalSource && !targetInput)) return;

    // Warning copy travels on the static total source when present, otherwise
    // on the form itself (the manual payment's target is a typed input).
    var messages = {
      empty: (totalSource && totalSource.dataset.paymentWarningEmpty) || form.dataset.paymentWarningEmpty || "",
      short: (totalSource && totalSource.dataset.paymentWarningShort) || form.dataset.paymentWarningShort || "",
      over: (totalSource && totalSource.dataset.paymentWarningOver) || form.dataset.paymentWarningOver || ""
    };

    function expectedTotal() {
      if (targetInput) return componentValue(targetInput);
      return parseFloat(totalSource.dataset.paymentExpenseTotal) || 0;
    }

    function update() {
      var total = inputs.reduce(function (sum, input) { return sum + componentValue(input); }, 0);
      var target = expectedTotal();
      var diff = total - target;

      display.textContent = "$" + formatMoney(total);

      var message = null;
      if (target <= 0 || total === 0) {
        message = messages.empty;
      } else if (diff < 0) {
        message = messages.short.replace(PLACEHOLDERS.short, formatMoney(diff));
      } else if (diff > 0) {
        message = messages.over.replace(PLACEHOLDERS.over, formatMoney(diff));
      }

      // While an AJAX submit is in flight the button stays disabled even if the
      // numbers still match.
      var submitting = form.dataset.manualSubmitting === "true";

      if (message) {
        warningText.textContent = message;
        warning.classList.remove("d-none");
        if (submit) submit.disabled = true;
      } else {
        warning.classList.add("d-none");
        if (submit) submit.disabled = submitting;
      }

      var amountInput = form.querySelector("[data-payment-amount]");
      if (amountInput) amountInput.value = total > 0 ? String(total) : "";
    }

    inputs.forEach(function (input) {
      input.addEventListener("input", update);
      input.addEventListener("blur", update);
    });
    if (targetInput) {
      targetInput.addEventListener("input", update);
      targetInput.addEventListener("blur", update);
    }
    update();
  }

  // The manual payment form creates the expense + payment in the background so
  // the modal can show validation errors inline and only leaves the page on
  // success (where the balance and history refresh).
  // Idempotency: the server refuses to create the same payment twice when the
  // same key arrives again (double submit, retry, or a stale script). Each
  // open of the modal starts a fresh key; retries of one submission keep it.
  function newIdempotencyKey() {
    return window.crypto && window.crypto.randomUUID ? window.crypto.randomUUID() : null;
  }

  function startIdempotencyKey(form) {
    var input = form.querySelector("[data-idempotency-key]");
    if (!input) return null;
    var key = newIdempotencyKey();
    if (key) input.value = key;
    return key;
  }

  function bindManualForm(form) {
    if (form.dataset.manualPaymentBound === "true") return;
    form.dataset.manualPaymentBound = "true";

    var error = form.querySelector("[data-manual-error]");
    var submit = form.querySelector("[data-manual-submit]");
    var spinner = form.querySelector("[data-manual-spinner]");
    var label = form.querySelector("[data-manual-submit-label]");
    var failed = form.dataset.manualFailed || "";
    var busyLabel = form.dataset.manualBusyLabel || "";
    if (label) label.dataset.idleLabel = label.textContent;

    var modal = form.closest(".modal");
    if (modal) {
      modal.addEventListener("show.bs.modal", function () {
        startIdempotencyKey(form);
      });
    } else {
      startIdempotencyKey(form);
    }

    function setBusy(busy) {
      form.dataset.manualSubmitting = busy ? "true" : "false";
      if (spinner) spinner.classList.toggle("d-none", !busy);
      if (label) label.textContent = busy ? busyLabel : (label.dataset.idleLabel || label.textContent);

      if (busy) {
        if (submit) submit.disabled = true;
        return;
      }
      // Releasing the button re-runs the distribution check so an out-of-balance
      // form stays blocked instead of becoming submittable.
      var component = form.querySelector("[data-payment-component='true']");
      if (component) component.dispatchEvent(new Event("input", { bubbles: true }));
      else if (submit) submit.disabled = false;
    }

    form.addEventListener("submit", function (event) {
      if (form.dataset.manualSubmitting === "true") {
        event.preventDefault();
        return;
      }
      if (!window.fetch) return; // progressive enhancement: fall back to a plain submit
      event.preventDefault();
      if (error) error.classList.add("d-none");
      setBusy(true);

      fetch(form.action, {
        method: "POST",
        headers: { "Accept": "application/json", "X-CSRF-Token": csrfToken() },
        body: new FormData(form),
        credentials: "same-origin"
      }).then(function (response) {
        return response.json().then(function (data) { return { ok: response.ok, data: data }; });
      }).then(function (result) {
        if (result.ok && result.data.ok && result.data.redirect_url) {
          window.location.assign(result.data.redirect_url);
          return;
        }
        setBusy(false);
        if (error) {
          error.textContent = (result.data.errors || []).join(" ") || failed;
          error.classList.remove("d-none");
        }
      }).catch(function () {
        setBusy(false);
        if (error) {
          error.textContent = failed;
          error.classList.remove("d-none");
        }
      });
    });
  }

  function init(root) {
    var scope = root || document;
    Array.prototype.slice.call(scope.querySelectorAll(FORM_SELECTOR)).forEach(bindForm);
    Array.prototype.slice.call(scope.querySelectorAll(MANUAL_FORM_SELECTOR)).forEach(bindManualForm);
  }

  window.PaymentDistribution = { init: init };

  document.addEventListener("DOMContentLoaded", function () { init(document); });
  document.addEventListener("turbo:load", function () { init(document); });
})();
