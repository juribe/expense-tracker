// Statement imports
// Client-side helpers for the "Create statement expenses" form:
//   - submit guard: a movement marked for creation must have a category
//   - select all / deselect all and a live selection count
//   - bulk category: assign one category to every selected movement via a modal
//   - pay-only mode: collapse the movements so the user can register just the
//     statement payment without importing any expense
//
// Expected markup: form[data-movement-form="true"] with rows
// [data-movement-row] holding a [data-movement-select="true"] checkbox and a
// [data-movement-category="true"] select, an optional [data-movement-select-all],
// [data-movement-selection-count], [data-movement-body], [data-movement-submit],
// [data-movement-pay-only], a [data-movement-error] target and a
// #bulkCategoryModal with [data-movement-bulk-category] / [data-movement-bulk-apply].
(function () {
  var FORM_SELECTOR = '[data-movement-form="true"]';
  // Only the statement-import payment form posts here and answers JSON. Other
  // payment distribution forms (apply an existing expense, manual payment) are
  // plain HTML forms owned by their controllers and must not be hijacked:
  // binding them would send an AJAX request whose redirect/render does not
  // support JSON and fail silently.
  var PAY_FORM_SELECTOR = '[data-statement-payment-form="true"]';
  var UPLOAD_FORM_SELECTOR = '[data-upload-form="true"]';

  function csrfToken() {
    var meta = document.querySelector("meta[name='csrf-token']");
    return meta ? meta.getAttribute("content") : "";
  }

  function form() {
    return document.querySelector(FORM_SELECTOR);
  }

  function rows(scope) {
    return Array.prototype.slice.call(scope.querySelectorAll("[data-movement-row]"));
  }

  function selectedRows(scope) {
    return rows(scope).filter(function (row) {
      var checkbox = row.querySelector("[data-movement-select='true']");
      return checkbox && checkbox.checked;
    });
  }

  function fillTemplate(element, count) {
    if (!element) return;
    element.textContent = count > 0 ? element.dataset.template.replace("__COUNT__", count) : "";
  }

  function updateSelection(scope) {
    var selected = selectedRows(scope).length;
    fillTemplate(scope.querySelector("[data-movement-selection-count]"), selected);

    var all = scope.querySelector("[data-movement-select-all]");
    if (all) {
      var total = rows(scope).length;
      all.checked = selected > 0 && selected === total;
      all.indeterminate = selected > 0 && selected < total;
    }

    var bulkOpen = scope.querySelector("[data-movement-bulk-open]");
    if (bulkOpen) bulkOpen.disabled = selected === 0;
  }

  function clearError(scope) {
    var error = scope.querySelector("[data-movement-error]");
    if (error) error.classList.add("d-none");
  }

  function uncategorizedSelected(scope) {
    return selectedRows(scope).filter(function (row) {
      var select = row.querySelector("[data-movement-category='true']");
      return select && select.value === "";
    });
  }

  function openBulk(scope) {
    var modal = document.getElementById("bulkCategoryModal");
    if (!modal) return;

    fillTemplate(modal.querySelector("[data-movement-bulk-count]"), selectedRows(scope).length);
    var category = modal.querySelector("[data-movement-bulk-category]");
    if (category) window.CategoryPicker.setValue(category, "");
    window.bootstrap.Modal.getOrCreateInstance(modal).show();
  }

  function applyBulk(scope) {
    var modal = document.getElementById("bulkCategoryModal");
    var category = modal && modal.querySelector("[data-movement-bulk-category]");
    if (!category || category.value === "") return;

    selectedRows(scope).forEach(function (row) {
      var select = row.querySelector("[data-movement-category='true']");
      if (!select) return;

      window.CategoryPicker.setValue(select, category.value);
    });

    window.bootstrap.Modal.getOrCreateInstance(modal).hide();
    updateSelection(scope);
  }

  function togglePayOnly(scope) {
    var button = scope.querySelector("[data-movement-pay-only]");
    var active = scope.dataset.payOnly === "true";
    var next = !active;
    scope.dataset.payOnly = next ? "true" : "false";

    var body = scope.querySelector("[data-movement-body]");
    var submit = scope.querySelector("[data-movement-submit]");
    var hint = scope.querySelector("[data-movement-pay-only-hint]");
    var label = scope.querySelector("[data-movement-pay-only-label]");

    if (body) body.classList.toggle("d-none", next);
    if (submit) submit.classList.toggle("d-none", next);
    if (hint) hint.classList.toggle("d-none", !next);
    if (label && button) {
      label.textContent = next ? button.dataset.movementPayOnlyActive : button.dataset.movementPayOnlyInactive;
    }
  }

  function bind(scope) {
    if (scope.dataset.movementBound === "true") return;
    scope.dataset.movementBound = "true";

    var error = scope.querySelector("[data-movement-error]");

    scope.addEventListener("submit", function (event) {
      var invalid = uncategorizedSelected(scope);
      if (invalid.length === 0) return;

      event.preventDefault();
      invalid.forEach(function (row) { row.classList.add("table-danger"); });
      if (error) {
        error.textContent = error.getAttribute("data-movement-error-message") || "";
        error.classList.remove("d-none");
        error.scrollIntoView({ behavior: "smooth", block: "center" });
      }
      var firstSelect = invalid[0].querySelector("[data-movement-category='true']");
      if (firstSelect) window.CategoryPicker.focus(firstSelect);
    });

    scope.addEventListener("change", function (event) {
      if (error) error.classList.add("d-none");
      var row = event.target.closest && event.target.closest("[data-movement-row]");
      if (row) row.classList.remove("table-danger");

      if (event.target.matches("[data-movement-select-all]")) {
        var checked = event.target.checked;
        rows(scope).forEach(function (item) {
          var checkbox = item.querySelector("[data-movement-select='true']");
          if (checkbox) checkbox.checked = checked;
        });
      }
      if (event.target.matches("[data-movement-select-all], [data-movement-select]")) {
        updateSelection(scope);
      }
    });

    updateSelection(scope);
  }

  function bindControls() {
    if (document.documentElement.dataset.movementControlsBound === "true") return;
    document.documentElement.dataset.movementControlsBound = "true";

    document.addEventListener("click", function (event) {
      var scope = form();
      if (!scope) return;

      if (event.target.closest("[data-movement-bulk-open]")) {
        openBulk(scope);
      } else if (event.target.closest("[data-movement-bulk-apply]")) {
        applyBulk(scope);
      } else if (event.target.closest("[data-movement-pay-only]")) {
        togglePayOnly(scope);
      }
    });
  }

  function removePaymentSection() {
    [ "statement-summary", "statement-payment-form" ].forEach(function (id) {
      var section = document.getElementById(id);
      if (section) section.remove();
    });
  }

  function showNotice(message) {
    if (!message) return;
    var container = document.querySelector(".content-wrapper") || document.body;
    var alert = document.createElement("div");
    alert.className = "alert alert-success alert-dismissible fade show";
    alert.setAttribute("role", "alert");
    alert.setAttribute("data-testid", "flash-notice");
    alert.appendChild(document.createTextNode(message));
    var close = document.createElement("button");
    close.type = "button";
    close.className = "btn-close";
    close.setAttribute("data-bs-dismiss", "alert");
    close.setAttribute("aria-label", "Close");
    alert.appendChild(close);
    container.insertBefore(alert, container.firstChild);
  }

  function showPayError(scope, errors) {
    var error = scope.querySelector("[data-payment-error]");
    if (!error) return;
    error.textContent = errors.length > 0 ? errors.join(" ") : (scope.dataset.paymentErrorMessage || "");
    error.classList.remove("d-none");
    error.scrollIntoView({ behavior: "smooth", block: "center" });
  }

  function setPayLoading(scope, busy) {
    var submit = scope.querySelector("[data-payment-submit]");
    var spinner = scope.querySelector("[data-payment-spinner]");
    var label = scope.querySelector("[data-payment-submit-label]");
    scope.dataset.paymentSubmitting = busy ? "true" : "false";
    if (submit) submit.disabled = busy;
    if (spinner) spinner.classList.toggle("d-none", !busy);
    if (label) {
      label.textContent = busy
        ? (label.dataset.busyLabel || label.textContent)
        : (label.dataset.idleLabel || label.textContent);
    }
  }

  function bindPayForm(scope) {
    if (scope.dataset.paymentAjaxBound === "true") return;
    scope.dataset.paymentAjaxBound = "true";

    var label = scope.querySelector("[data-payment-submit-label]");
    if (label) {
      label.dataset.idleLabel = label.textContent;
      label.dataset.busyLabel = scope.dataset.paymentBusyLabel || label.textContent;
    }

    scope.addEventListener("submit", function (event) {
      event.preventDefault();
      if (scope.dataset.paymentSubmitting === "true") return;
      setPayLoading(scope, true);

      var error = scope.querySelector("[data-payment-error]");
      if (error) error.classList.add("d-none");

      fetch(scope.action, {
        method: "POST",
        headers: { "Accept": "application/json", "X-CSRF-Token": csrfToken() },
        body: new FormData(scope),
        credentials: "same-origin"
      }).then(function (response) {
        return response.json().then(function (data) { return { ok: response.ok, data: data }; });
      }).then(function (result) {
        if (result.ok && result.data.success) {
          removePaymentSection();
          showNotice(result.data.notice);
        } else {
          setPayLoading(scope, false);
          showPayError(scope, result.data.errors || []);
        }
      }).catch(function () {
        setPayLoading(scope, false);
        showPayError(scope, []);
      });
    });
  }

  // ------------------------------------------------------------ upload (AJAX)
  // The "Importar extracto" form posts the file in the background so the page
  // never goes blank while the statement is parsed. Two stages are surfaced:
  // uploading the file (with a real byte-progress bar) and analyzing it on the
  // server. On success the returned review HTML replaces the upload screen in
  // place; on failure the error shows inline and the chosen file is kept.

  function setUploadStep(steps, step, state, percent) {
    if (!steps) return;
    var item = steps.querySelector('[data-step="' + step + '"]');
    if (!item) return;

    var spinner = item.querySelector("[data-step-spinner]");
    var done = item.querySelector("[data-step-done]");
    var idle = item.querySelector("[data-step-idle]");
    if (spinner) spinner.classList.toggle("d-none", state !== "active");
    if (done) done.classList.toggle("d-none", state !== "done");
    if (idle) idle.classList.toggle("d-none", state !== "idle");

    var readout = item.querySelector("[data-step-percent]");
    if (readout) readout.textContent = percent == null ? "" : Math.round(percent) + "%";
  }

  function rebindReview(scope) {
    if (!scope) return;
    if (window.CategoryPicker && window.CategoryPicker.bindAll) window.CategoryPicker.bindAll(scope);
    if (window.StatementImports && window.StatementImports.init) window.StatementImports.init(scope);
    if (window.PaymentDistribution && window.PaymentDistribution.init) window.PaymentDistribution.init(scope);
    if (window.MoneyInputs && window.MoneyInputs.init) window.MoneyInputs.init(scope);
  }

  function swapToReview(root, html) {
    if (!root || !html) { window.location.reload(); return; }
    var template = document.createElement("template");
    template.innerHTML = html.trim();
    var replacement = template.content.firstElementChild;
    if (!replacement) return;
    root.replaceWith(replacement);
    rebindReview(replacement);
    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  function bindUploadForm(scope) {
    if (scope.dataset.uploadAjaxBound === "true") return;
    scope.dataset.uploadAjaxBound = "true";

    var root = document.querySelector("[data-statement-import-root]");
    var progress = document.getElementById("statementImportProgress");
    var steps = progress && progress.querySelector("[data-statement-import-steps]");
    var bar = progress && progress.querySelector("[data-step-bar]");
    var errorBox = document.getElementById("statementImportError");
    var submit = scope.querySelector("button[type='submit'], input[type='submit']");

    function showError(message) {
      if (!errorBox) return;
      errorBox.textContent = message || "";
      errorBox.classList.remove("d-none");
      errorBox.scrollIntoView({ behavior: "smooth", block: "center" });
    }

    scope.addEventListener("submit", function (event) {
      var fileInput = scope.querySelector("input[type='file']");
      if (!window.XMLHttpRequest || !fileInput || !fileInput.files.length) return;

      event.preventDefault();
      if (errorBox) errorBox.classList.add("d-none");
      if (progress) progress.classList.remove("d-none");
      setUploadStep(steps, "upload", "active", 0);
      setUploadStep(steps, "analyze", "idle");
      if (bar) bar.style.width = "0%";
      if (submit) submit.disabled = true;

      var xhr = new XMLHttpRequest();
      xhr.open("POST", scope.action, true);
      xhr.setRequestHeader("Accept", "application/json");
      xhr.setRequestHeader("X-CSRF-Token", csrfToken());

      xhr.upload.addEventListener("progress", function (e) {
        if (!e.lengthComputable) return;
        var pct = (e.loaded / e.total) * 100;
        if (bar) bar.style.width = pct + "%";
        setUploadStep(steps, "upload", "active", pct);
      });

      xhr.upload.addEventListener("load", function () {
        if (bar) bar.style.width = "100%";
        setUploadStep(steps, "upload", "done", 100);
        setUploadStep(steps, "analyze", "active");
      });

      xhr.addEventListener("load", function () {
        if (submit) submit.disabled = false;
        var data = {};
        try { data = JSON.parse(xhr.responseText); } catch (e) { /* keep {} */ }

        if (xhr.status >= 200 && xhr.status < 300 && data.ok && data.html) {
          setUploadStep(steps, "analyze", "done");
          swapToReview(root, data.html);
          return;
        }

        setUploadStep(steps, "analyze", "idle");
        if (bar) bar.style.width = "0%";
        var errors = (data.errors || []).join(" ");
        showError(errors || scope.dataset.uploadFailed || "");
      });

      xhr.addEventListener("error", function () {
        if (submit) submit.disabled = false;
        setUploadStep(steps, "analyze", "idle");
        if (bar) bar.style.width = "0%";
        showError(scope.dataset.uploadFailed || "");
      });

      xhr.send(new FormData(scope));
    });
  }

  function init(root) {
    var scope = root || document;
    scope.querySelectorAll(FORM_SELECTOR).forEach(bind);
    scope.querySelectorAll(PAY_FORM_SELECTOR).forEach(bindPayForm);
    scope.querySelectorAll(UPLOAD_FORM_SELECTOR).forEach(bindUploadForm);
    bindControls();
  }

  // Exposed so the review HTML injected after an AJAX upload can be re-bound.
  window.StatementImports = { init: init };

  document.addEventListener("DOMContentLoaded", function () { init(document); });
  document.addEventListener("turbo:load", function () { init(document); });
})();
