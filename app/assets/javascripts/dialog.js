(function () {
  if (window.Dialog) return;

  var activeModal = null;
  var activeResolver = null;

  function escapeHtml(value) {
    return String(value == null ? "" : value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function variantClass(variant) {
    if (variant === "danger") return "btn btn-danger";
    if (variant === "warning") return "btn btn-warning";
    if (variant === "success") return "btn btn-success";
    if (variant === "white") return "btn btn-white";
    return "btn btn-primary";
  }

  function normalizeOptions(message, options) {
    if (typeof options === "string") options = { title: options };
    options = options || {};
    if (message === undefined || message === null) message = "";
    return { message: String(message), options: options };
  }

  function init(message, options) {
    var normalized = normalizeOptions(message, options);
    message = normalized.message;
    options = normalized.options;

    var types = window.Dialog.types;
    var type = options.type || types.ALERT;
    var title = options.title;
    var confirmLabel = options.confirmLabel || (type === types.CONFIRM ? "Confirmar" : "Aceptar");
    var cancelLabel = options.cancelLabel || "Cancelar";
    var variant = options.variant || "primary";
    var dialogType = options.dialogType || "";
    var bodyHtml = options.bodyHtml || "";
    var footerHtml = options.footerHtml || "";
    var onValidate = typeof options.onValidate === "function" ? options.onValidate : null;
    var onRender = typeof options.onRender === "function" ? options.onRender : null;
    var target = options.target || null;

    if (typeof bootstrap === "undefined") {
      // Fallback to native dialogs when Bootstrap is not available.
      if (type === types.ALERT) {
        window.alert(message);
        return Promise.resolve(true);
      }
      return Promise.resolve(window.confirm(message));
    }

    var el = document.createElement("div");
    el.className = "modal fade confirmation-modal" + (dialogType ? " confirmation-modal--" + dialogType : "");
    el.setAttribute("tabindex", "-1");
    el.setAttribute("aria-hidden", "true");
    el.setAttribute("role", "dialog");
    el.setAttribute("data-testid", "dialog-modal");

    var iconClass = variant === "danger" ? "ti ti-alert-triangle text-danger" :
                    variant === "warning" ? "ti ti-alert-circle text-warning" :
                    variant === "success" ? "ti ti-circle-check text-success" :
                    "ti ti-help-circle text-primary";
    var headerHtml = title
      ? '<div class="modal-header"><h5 class="modal-title"><i class="' + iconClass + ' me-2"></i>' + escapeHtml(title) + '</h5><button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button></div>'
      : '<div class="modal-header"><button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button></div>';

    var cancelBtn = (type === types.CONFIRM || type === types.SUBMIT_ACTION)
      ? '<button type="button" class="btn btn-outline-secondary" data-ref="cancel" data-testid="dialog-cancel">' + escapeHtml(cancelLabel) + '</button>'
      : "";

    var acceptBtn = '<button type="button" class="' + variantClass(variant) + '" data-ref="accept" data-testid="dialog-accept">' + escapeHtml(confirmLabel) + '</button>';

    var footerContent = footerHtml ? footerHtml : (cancelBtn + acceptBtn);

    el.innerHTML =
      '<div class="modal-dialog modal-sm">' +
        '<div class="modal-content">' +
          headerHtml +
          '<div class="modal-body">' +
            '<p class="mb-0" data-ref="message">' + escapeHtml(message) + '</p>' +
            bodyHtml +
          '</div>' +
          '<div class="modal-footer">' + footerContent + '</div>' +
        '</div>' +
      '</div>';

    document.body.appendChild(el);

    var elements = {};
    el.querySelectorAll("[data-ref]").forEach(function (node) {
      elements[node.dataset.ref] = node;
    });

    if (onRender) onRender(el);

    var modal = bootstrap.Modal.getOrCreateInstance(el, { backdrop: true, keyboard: true, focus: true });
    activeModal = modal;

    el.addEventListener("shown.bs.modal", function () {
      var btn = el.querySelector("[data-ref=accept]");
      if (btn) btn.focus();
    }, { once: true });

    try { modal.show(); } catch (e) { console.error("MODAL SHOW ERROR", e); }

    return new Promise(function (resolve) {
      activeResolver = resolve;
      var resolved = false;

      function resolveOnce(value) {
        if (resolved) return;
        resolved = true;
        if (activeResolver === resolve) activeResolver = null;
        resolve(value);
      }

      function closeModal(value) {
        resolveOnce(value);
        try { modal.hide(); } catch (e) {}
      }

      var acceptBtnEl = el.querySelector("[data-ref=accept]");
      var cancelBtnEl = el.querySelector("[data-ref=cancel]");

      function onAccept(e) {
        if (e) e.preventDefault();
        if (onValidate && !onValidate(el)) return;
        if (target) {
          try {
            var attr = target.getAttribute("data-confirm");
            target.removeAttribute("data-confirm");
            var disabled = target.getAttribute("disabled");
            if (disabled !== null) target.removeAttribute("disabled");
            if (typeof target.click === "function") target.click();
            if (attr !== null) target.setAttribute("data-confirm", attr);
            if (disabled !== null) target.setAttribute("disabled", disabled);
          } catch (err) {}
        }
        closeModal(true);
      }

      function onCancel(e) {
        if (e) e.preventDefault();
        closeModal(false);
      }

      if (acceptBtnEl) acceptBtnEl.addEventListener("click", onAccept);
      if (cancelBtnEl) cancelBtnEl.addEventListener("click", onCancel);

      el.addEventListener("keydown", function (e) {
        if (e.key === "Enter" && e.target && e.target.tagName !== "TEXTAREA") {
          e.preventDefault();
          onAccept(e);
        } else if (e.key === "Escape") {
          e.preventDefault();
          if (cancelBtnEl) onCancel(e);
          else closeModal(type === types.ALERT);
        } else if (e.key === "Tab") {
          e.preventDefault();
          if (acceptBtnEl) acceptBtnEl.focus();
        }
      });

      el.addEventListener("hidden.bs.modal", function () {
        if (!resolved) {
          resolveOnce(type === types.ALERT ? true : false);
        }
        if (el.parentNode) el.parentNode.removeChild(el);
        if (activeModal === modal) activeModal = null;
      }, { once: true });
    });
  }

  window.Dialog = {
    types: { ALERT: "ALERT", CONFIRM: "CONFIRM", SUBMIT_ACTION: "SUBMIT_ACTION" },
    init: init,
    alert: function (message, options) {
      options = options || {};
      return init(message, Object.assign({}, options, { type: window.Dialog.types.ALERT }));
    },
    confirm: function (message, options) {
      if (typeof options === "string") options = { title: options };
      options = options || {};
      return init(message, Object.assign({}, options, { type: window.Dialog.types.CONFIRM }));
    },
    dataConfirm: function (target, message, options) {
      options = options || {};
      options.target = target;
      if (message !== undefined) options.message = message;
      return init(options.message || (target && target.getAttribute ? target.getAttribute("data-confirm") : "") || "", Object.assign({}, options, { type: window.Dialog.types.CONFIRM }));
    },
    submitAction: function (options) {
      options = options || {};
      return init(options.message || "", Object.assign({}, options, { type: window.Dialog.types.SUBMIT_ACTION }));
    }
  };

  // Safe overrides (Promise-based). All app call sites must be migrated first.
  window.alert = function (message) {
    return window.Dialog.alert(message);
  };
  window.confirm = function (message, options) {
    return window.Dialog.confirm(message, options);
  };
})();
