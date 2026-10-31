(function () {
  // Guided money-source recognition MODAL.
  //
  // Every payment source is a step inside one modal. The wizard reuses the
  // recognition chip components and the manual PATCH endpoint (JSON), and
  // mirrors the single canonical keyword editor into the natural-language
  // section so both views always show the same persisted values.

  function escapeRegExp(value) {
    return String(value).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  }

  function canonicalContainer(form) {
    return form.querySelector("[data-recognition-chips='keywords']");
  }

  function aliasContainer(form) {
    return form.querySelector("[data-guided-alias-chips]");
  }

  function keywordValues(form) {
    var canonical = canonicalContainer(form);
    if (!canonical) return [];

    return Array.prototype.map
      .call(canonical.querySelectorAll("input[name='keywords[]']"), function (input) {
        return input.value;
      })
      .filter(function (value) { return value.trim() !== ""; });
  }

  function removeLabel(form) {
    return form.dataset.labelRemove || "Quitar";
  }

  function makeCanonicalChip(form, value) {
    var chip = document.createElement("span");
    chip.className = "recognition-chip";
    chip.setAttribute("data-testid", "recognition-chip");
    chip.setAttribute("data-chip-value", value);
    chip.appendChild(document.createTextNode(value));

    var hidden = document.createElement("input");
    hidden.type = "hidden";
    hidden.name = "keywords[]";
    hidden.value = value;
    chip.appendChild(hidden);

    var remove = document.createElement("button");
    remove.type = "button";
    remove.className = "recognition-chip-remove";
    remove.setAttribute("data-recognition-remove", "");
    remove.setAttribute("aria-label", removeLabel(form));
    remove.innerHTML = '<i class="ti ti-x"></i>';
    chip.appendChild(remove);

    return chip;
  }

  function makeAliasChip(form, value) {
    var chip = document.createElement("span");
    chip.className = "recognition-chip guided-alias-chip";
    chip.setAttribute("data-testid", "guided-alias-chip");
    chip.setAttribute("data-alias-value", value);
    chip.appendChild(document.createTextNode(value));

    var remove = document.createElement("button");
    remove.type = "button";
    remove.className = "recognition-chip-remove";
    remove.setAttribute("data-guided-alias-remove", "");
    remove.setAttribute("aria-label", removeLabel(form));
    remove.innerHTML = '<i class="ti ti-x"></i>';
    chip.appendChild(remove);

    return chip;
  }

  function mirrorAliases(form) {
    var target = aliasContainer(form);
    if (!target) return;

    target.textContent = "";
    keywordValues(form).forEach(function (value) {
      target.appendChild(makeAliasChip(form, value));
    });
  }

  function renderHighlight(element, values, markClass) {
    var text = element.getAttribute("data-text") || element.textContent || "";
    var raw = values.filter(function (value) { return String(value).trim() !== ""; });
    element.textContent = "";

    if (raw.length === 0) {
      element.appendChild(document.createTextNode(text));
      return;
    }

    var pattern = new RegExp(
      "(" + raw.sort(function (a, b) { return b.length - a.length; })
                   .map(escapeRegExp)
                   .join("|") + ")",
      "gi"
    );

    text.split(pattern).forEach(function (part, index) {
      if (index % 2 === 1 && part) {
        var mark = document.createElement("mark");
        mark.className = markClass || "guided-highlight";
        mark.textContent = part;
        element.appendChild(mark);
      } else if (part) {
        element.appendChild(document.createTextNode(part));
      }
    });
  }

  function refreshHighlights(form) {
    var values = keywordValues(form);

    form.querySelectorAll("[data-guided-highlight]").forEach(function (element) {
      var selected = values;
      var source = element.getAttribute("data-highlight-source");
      var keywordMatched = false;

      if (source === "alias") {
        var index = parseInt(element.getAttribute("data-alias-index") || "0", 10);
        var fallback = element.getAttribute("data-fallback-alias") || "";
        var alias = values[index] || values[0] || fallback;
        selected = alias ? [ alias ] : [];

        // The chat sentence is rebuilt around the selected alias so the
        // example follows the words the user is configuring right now.
        var prefix = element.getAttribute("data-prefix");
        var suffix = element.getAttribute("data-suffix");
        if (prefix !== null && suffix !== null) {
          element.setAttribute("data-text", prefix + alias + suffix);
        }
      }

      if (source === "keywords") {
        var body = (element.getAttribute("data-text") || "").toLowerCase();
        var matchedValues = values.filter(function (value) {
          return body.indexOf(String(value).toLowerCase()) >= 0;
        });
        keywordMatched = matchedValues.length > 0;

        // Always underline a reference from the sample: configured criteria
        // when present, otherwise the source's last four or name.
        if (keywordMatched) {
          selected = matchedValues;
        } else {
          var sample = element.getAttribute("data-fallback-highlight");
          selected = sample ? [ sample ] : [];
        }
      }

      renderHighlight(element, selected, element.getAttribute("data-mark-class"));

      if (source === "keywords") {
        var mailBody = element.closest(".guided-mail-body");
        if (mailBody) {
          var example = mailBody.querySelector("[data-guided-caption-example]");
          var configured = mailBody.querySelector("[data-guided-caption-configured]");
          if (example) example.classList.toggle("d-none", keywordMatched);
          if (configured) configured.classList.toggle("d-none", !keywordMatched);
        }
      }
    });
  }

  function addValue(form, inputSelector) {
    var input = form.querySelector(inputSelector);
    var canonical = canonicalContainer(form);
    if (!input || !canonical) return;

    var values = input.value.split(",")
      .map(function (value) { return value.trim(); })
      .filter(function (value) { return value !== ""; });
    if (values.length === 0) return;

    var existing = keywordValues(form).map(function (value) { return value.toLowerCase(); });
    values.forEach(function (value) {
      var key = value.toLowerCase();
      if (existing.indexOf(key) >= 0) return;

      canonical.appendChild(makeCanonicalChip(form, value));
      existing.push(key);
    });

    input.value = "";
    mirrorAliases(form);
    refreshHighlights(form);
  }

  function addKeyword(form) {
    addValue(form, "[data-guided-keyword-input]");
  }

  function addAlias(form) {
    addValue(form, "[data-guided-alias-input]");
  }

  function removeAlias(form, value) {
    var canonical = canonicalContainer(form);
    if (!canonical) return;

    // Match the canonical chip by its submitted value, not by a data attribute:
    // chips accepted from the suggestion block are created by the shared
    // recognition component and do not carry data-chip-value.
    Array.prototype.forEach.call(
      canonical.querySelectorAll(".recognition-chip"),
      function (chip) {
        var input = chip.querySelector("input[name='keywords[]']");
        if (input && input.value === value) chip.remove();
      }
    );
    mirrorAliases(form);
    refreshHighlights(form);
  }

  function markDirty(form) {
    form.dataset.guidedDirty = "true";
  }

  function bindStepForm(form) {
    if (form.dataset.guidedBound === "true") return;
    form.dataset.guidedBound = "true";

    var canonical = canonicalContainer(form);
    if (!canonical) return;

    mirrorAliases(form);
    refreshHighlights(form);

    new MutationObserver(function () {
      mirrorAliases(form);
      refreshHighlights(form);
      markDirty(form);
    }).observe(canonical, { childList: true });

    form.addEventListener("click", function (event) {
      var keywordButton = event.target.closest("[data-guided-keyword-add]");
      if (keywordButton) {
        event.preventDefault();
        addKeyword(form);
        markDirty(form);
        return;
      }

      var addButton = event.target.closest("[data-guided-alias-add]");
      if (addButton) {
        event.preventDefault();
        addAlias(form);
        markDirty(form);
        return;
      }

      var removeButton = event.target.closest("[data-guided-alias-remove]");
      if (removeButton) {
        event.preventDefault();
        var chip = removeButton.closest("[data-alias-value]");
        if (chip) removeAlias(form, chip.getAttribute("data-alias-value"));
        markDirty(form);
      }
    });

    form.addEventListener("keydown", function (event) {
      if (event.key !== "Enter") return;

      if (event.target.matches("[data-guided-keyword-input]")) {
        event.preventDefault();
        addKeyword(form);
        markDirty(form);
      } else if (event.target.matches("[data-guided-alias-input]")) {
        event.preventDefault();
        addAlias(form);
        markDirty(form);
      }
    });
  }

  function csrfToken() {
    var meta = document.querySelector("meta[name='csrf-token']");
    return meta ? meta.getAttribute("content") : "";
  }

  function bindModal(modal) {
    if (modal.dataset.guidedBound === "true") return;
    modal.dataset.guidedBound = "true";

    var forms = Array.prototype.slice.call(modal.querySelectorAll("[data-guided-step-form]"));
    var items = Array.prototype.slice.call(modal.querySelectorAll("[data-guided-go]"));
    var previous = modal.querySelector("[data-guided-previous]");
    var save = modal.querySelector("[data-guided-save]");
    var saveLabel = modal.querySelector("[data-guided-save-label]");
    var saveExit = modal.querySelector("[data-guided-save-exit]");
    var dismiss = modal.querySelector("[data-guided-dismiss]");
    var errorBox = modal.querySelector("[data-guided-error]");
    var main = modal.querySelector("[data-guided-main]");
    var intro = modal.querySelector("[data-guided-intro]");
    var progressText = modal.querySelector("[data-guided-progress-text]");
    var progressBar = modal.querySelector("[data-guided-progress-bar]");
    var progressTrack = modal.querySelector(".guided-progress-track");
    var active = -1;
    var saving = false;

    forms.forEach(bindStepForm);

    function activeForm() {
      return forms[active];
    }

    function total() {
      return forms.length;
    }

    function showError(message) {
      if (!errorBox) return;
      errorBox.textContent = message;
      errorBox.hidden = false;
    }

    function clearError() {
      if (!errorBox) return;
      errorBox.textContent = "";
      errorBox.hidden = true;
    }

    function setConfigured(form, configured) {
      form.dataset.configured = configured ? "true" : "false";

      var item = items[parseInt(form.getAttribute("data-guided-step-index"), 10)];
      if (!item) return;

      item.dataset.configured = configured ? "true" : "false";
      item.classList.toggle("is-configured", configured);

      var state = item.querySelector("[data-testid='guided-source-state']");
      if (state) {
        state.textContent = configured ? modal.dataset.stateConfigured : modal.dataset.statePending;
        state.classList.toggle("guided-source-ok", configured);
        state.classList.toggle("guided-source-pending", !configured);
      }

      var tick = item.querySelector("[data-guided-tick]");
      if (tick) tick.classList.toggle("d-none", !configured);

      updateProgress();
    }

    function updateProgress() {
      var configured = forms.filter(function (form) {
        return form.dataset.configured === "true";
      }).length;
      var count = total();
      var template = modal.dataset.progressTemplate || "%{configured} de %{total}";

      if (progressText) {
        progressText.textContent = template
          .replace("%{configured}", configured)
          .replace("%{total}", count);
      }

      if (progressTrack) {
        progressTrack.setAttribute("aria-valuenow", configured);
      }

      if (progressBar) {
        var percentage = count === 0 ? 0 : Math.round(configured / count * 100);
        progressBar.className = progressBar.className.replace(/et-w-\d+/, "et-w-" + percentage);
      }
    }

    function updateFooter() {
      var isIntro = active === -1;
      if (previous) {
        previous.classList.toggle("d-none", isIntro);
        previous.disabled = false;
      }
      if (!saveLabel || saving) return;

      if (isIntro) {
        saveLabel.textContent = modal.dataset.labelStart;
      } else {
        saveLabel.textContent = active === total() - 1
          ? modal.dataset.labelFinish
          : modal.dataset.labelSave;
      }
    }

    function showStep(index) {
      if (total() === 0) return;

      var isIntro = index < 0;
      if (isIntro) {
        active = -1;
        if (intro) intro.classList.remove("d-none");
        forms.forEach(function (form) { form.classList.add("d-none"); });
        items.forEach(function (item) {
          item.classList.remove("is-active");
          item.setAttribute("aria-current", "false");
        });
      } else {
        active = Math.max(0, Math.min(index, total() - 1));
        if (intro) intro.classList.add("d-none");
        forms.forEach(function (form, position) {
          form.classList.toggle("d-none", position !== active);
        });
        items.forEach(function (item, position) {
          item.classList.toggle("is-active", position === active);
          if (position === active) item.setAttribute("aria-current", "step");
          else item.setAttribute("aria-current", "false");
        });
      }

      clearError();
      updateFooter();
      if (main) main.scrollTop = 0;
    }

    function setBusy(busy) {
      saving = busy;
      if (save) save.disabled = busy;
      if (saveExit) saveExit.disabled = busy;
      if (previous) previous.disabled = busy;

      if (!saveLabel) return;
      if (busy) {
        saveLabel.textContent = modal.dataset.labelSaving;
      } else {
        updateFooter();
      }
    }

    function clearSavedSuggestions(form) {
      var values = keywordValues(form);
      form.querySelectorAll(".recognition-chip-suggested").forEach(function (chip) {
        if (values.indexOf(chip.getAttribute("data-suggested-value")) >= 0) chip.remove();
      });
    }

    function finish() {
      deleteFormDirtyState();
      window.location.href = modal.dataset.finishUrl;
    }

    function deleteFormDirtyState() {
      forms.forEach(function (form) { delete form.dataset.guidedDirty; });
    }

    function saveForm(form) {
      clearError();
      setBusy(true);

      return fetch(form.action, {
        method: "POST",
        headers: {
          "Accept": "application/json",
          "X-CSRF-Token": csrfToken()
        },
        body: new FormData(form),
        credentials: "same-origin"
      }).then(function (response) {
        return response.json().then(
          function (body) { return { ok: response.ok, body: body }; },
          function () { return { ok: false, body: {} }; }
        );
      }).then(function (result) {
        setBusy(false);

        if (!result.ok) {
          var errors = Array.isArray(result.body.errors) ? result.body.errors.join(" ") : "";
          var failedIndex = forms.indexOf(form);
          if (failedIndex >= 0) showStep(failedIndex);
          showError(errors || modal.dataset.errorGeneric);
          return false;
        }

        setConfigured(form, result.body.configured === true);
        delete form.dataset.guidedDirty;
        clearSavedSuggestions(form);
        return true;
      }).catch(function () {
        setBusy(false);
        showError(modal.dataset.errorGeneric);
        return false;
      });
    }

    function saveStep(exitAfter) {
      if (active === -1) {
        if (exitAfter) {
          finish();
          return;
        }
        showStep(0);
        return;
      }

      if (saving || total() === 0) return;

      if (exitAfter) {
        saveAllAndExit();
        return;
      }

      saveForm(activeForm()).then(function (saved) {
        if (!saved) return;
        if (active === total() - 1) {
          finish();
          return;
        }
        showStep(active + 1);
      });
    }

    // "Guardar y salir" saves the visible step plus every other step with
    // unsaved edits, so leaving the modal never silently drops work.
    function saveAllAndExit() {
      var currentForm = activeForm();
      var queue = forms.filter(function (form) {
        return form === currentForm || form.dataset.guidedDirty === "true";
      });
      if (queue.indexOf(currentForm) === -1) queue.unshift(currentForm);
      saveQueue(queue, 0);
    }

    function saveQueue(queue, position) {
      if (position >= queue.length) {
        finish();
        return;
      }

      saveForm(queue[position]).then(function (saved) {
        if (saved) saveQueue(queue, position + 1);
      });
    }

    function anyDirty() {
      return forms.some(function (form) { return form.dataset.guidedDirty === "true"; });
    }

    function hideModal() {
      if (!window.bootstrap) return;
      window.bootstrap.Modal.getOrCreateInstance(modal).hide();
    }

    function confirmDiscard(callback) {
      if (!anyDirty()) {
        callback();
        return;
      }

      var confirmFn = (window.Dialog && typeof window.Dialog.confirm === "function")
        ? window.Dialog.confirm.bind(window.Dialog)
        : function (message) { return Promise.resolve(window.confirm(message)); };

      confirmFn(modal.dataset.unsavedMessage, {
        title: "Confirmar",
        confirmLabel: "Salir",
        variant: "warning"
      }).then(function (confirmed) {
        if (confirmed) callback();
      });
    }

    function requestClose() {
      if (saving) return;
      confirmDiscard(hideModal);
    }

    items.forEach(function (item, position) {
      item.addEventListener("click", function () { showStep(position); });
    });

    if (previous) previous.addEventListener("click", function () { showStep(active - 1); });
    if (save) save.addEventListener("click", function () { saveStep(false); });
    if (saveExit) saveExit.addEventListener("click", function () { saveStep(true); });
    if (dismiss) dismiss.addEventListener("click", requestClose);

    forms.forEach(function (form) {
      form.addEventListener("submit", function (event) {
        event.preventDefault();
        saveStep(false);
      });
    });

    showStep(-1);
    updateProgress();

    if (modal.dataset.autoOpen === "true" && window.bootstrap) {
      window.bootstrap.Modal.getOrCreateInstance(modal).show();
    }
  }

  // Later opens reuse the modal already rendered with ?guided=1, preserving
  // unsaved edits and the step the user was on.
  document.addEventListener("click", function (event) {
    if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey ||
        event.shiftKey || event.altKey) return;

    var opener = event.target.closest("[data-guided-wizard-open]");
    if (!opener) return;

    var modal = document.querySelector("[data-guided-wizard]");
    if (!modal || !window.bootstrap) return;

    event.preventDefault();
    window.bootstrap.Modal.getOrCreateInstance(modal).show();
  });

  function init() {
    document.querySelectorAll("[data-guided-wizard]").forEach(bindModal);
  }

  document.addEventListener("DOMContentLoaded", init);
  document.addEventListener("turbo:load", init);
  init();
})();
