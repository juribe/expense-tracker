// Contáctanos form: progressive AJAX submission with accessible states.
// The form still works without JavaScript through a normal POST + redirect.
(function () {
  "use strict";

  function init() {
    var form = document.querySelector("[data-contact-form]");
    if (!form || form.dataset.contactFormReady === "true") return;
    form.dataset.contactFormReady = "true";

    var panel = form.closest(".contact-form-panel");
    var status = panel ? panel.querySelector("[data-contact-status]") : null;
    var subjectSelect = form.querySelector("[data-contact-subject]");
    var submitButton = form.querySelector("[data-contact-submit]");
    var submitLabel = submitButton ? submitButton.querySelector("[data-contact-submit-label]") : null;
    var reasonButtons = document.querySelectorAll("[data-contact-reason]");
    var originalSubmitLabel = submitLabel ? submitLabel.textContent : "";
    var sendingLabel = submitButton ? submitButton.dataset.sendingLabel || "Enviando mensaje..." : "";
    var successTitle = form.dataset.successTitle || "¡Mensaje enviado!";
    var successText = form.dataset.successText || "";
    var errorText = form.dataset.errorText || "No pudimos enviar tu mensaje. Revisa los datos e inténtalo de nuevo.";

    function setReason(button) {
      reasonButtons.forEach(function (item) {
        item.setAttribute("aria-pressed", item === button ? "true" : "false");
      });

      if (subjectSelect && button && button.dataset.contactReason) {
        subjectSelect.value = button.dataset.contactReason;
      }
    }

    reasonButtons.forEach(function (button) {
      if (button.dataset.contactReasonReady === "true") return;
      button.dataset.contactReasonReady = "true";
      button.addEventListener("click", function () {
        setReason(button);
      });
    });

    function clearStatus() {
      if (!status) return;
      status.hidden = true;
      status.className = "contact-form-status";
      status.textContent = "";
    }

    function showStatus(kind, title, text) {
      if (!status) return;
      status.hidden = false;
      status.className = "contact-form-status is-" + kind;
      status.textContent = "";

      var strong = document.createElement("strong");
      strong.textContent = title;
      status.appendChild(strong);

      if (text) {
        var span = document.createElement("span");
        span.textContent = text;
        status.appendChild(span);
      }
    }

    function clearFieldErrors() {
      form.querySelectorAll("[data-contact-error-for]").forEach(function (element) {
        element.textContent = "";
        element.hidden = true;
      });
      form.querySelectorAll("[aria-invalid='true']").forEach(function (input) {
        input.removeAttribute("aria-invalid");
        input.classList.remove("is-invalid");
      });
    }

    function showFieldErrors(errors) {
      Object.keys(errors || {}).forEach(function (field) {
        var errorElement = form.querySelector("[data-contact-error-for='" + field + "']");
        var input = form.querySelector("[name='contact_message[" + field + "]']");
        var messages = Array.isArray(errors[field]) ? errors[field] : [errors[field]];

        if (errorElement) {
          errorElement.textContent = messages.join(" ");
          errorElement.hidden = false;
        }

        if (input) {
          input.setAttribute("aria-invalid", "true");
          input.classList.add("is-invalid");
        }
      });
    }

    function setSubmitting(submitting) {
      form.dataset.submitting = submitting ? "true" : "false";

      if (submitButton) {
        submitButton.disabled = submitting;
      }

      if (submitLabel) {
        submitLabel.textContent = submitting ? sendingLabel : originalSubmitLabel;
      }
    }

    function csrfToken() {
      var meta = document.querySelector("meta[name='csrf-token']");
      return meta ? meta.getAttribute("content") : "";
    }

    function parseJson(response) {
      var contentType = response.headers.get("Content-Type") || "";
      if (!contentType.includes("application/json")) {
        throw new Error("Unexpected response");
      }
      return response.json();
    }

    form.addEventListener("submit", function (event) {
      event.preventDefault();

      if (form.dataset.submitting === "true") return;

      if (!form.checkValidity()) {
        form.reportValidity();
        return;
      }

      setSubmitting(true);
      clearStatus();
      clearFieldErrors();

      fetch(form.action, {
        method: "POST",
        body: new FormData(form),
        credentials: "same-origin",
        headers: {
          "Accept": "application/json",
          "X-CSRF-Token": csrfToken()
        }
      })
        .then(function (response) {
          return parseJson(response).then(function (data) {
            return { ok: response.ok, data: data };
          });
        })
        .then(function (result) {
          if (result.ok) {
            form.reset();
            setReason(reasonButtons[0]);
            showStatus("success", successTitle, successText);
          } else {
            showStatus("error", result.data.error || errorText, "");
            showFieldErrors(result.data.errors);
          }
        })
        .catch(function () {
          showStatus("error", errorText, "");
        })
        .finally(function () {
          setSubmitting(false);
        });
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
