(function () {
  // ---------------------------------------------------------------- Bank setup wizard
  // Server-rendered steps, client-side navigation and per-bank saving through
  // the existing PATCH recognition endpoint (JSON). The wizard never invents
  // recognition rules: chips are submitted with the same field names the
  // manual drawer uses and the endpoint classifies/validates them.
  var STORAGE_PREFIX = "bankSetupWizard";

  function storageKey(modal, name) {
    return STORAGE_PREFIX + ":" + name + ":" + (modal.dataset.userId || "anon");
  }

  function readSet(modal, name) {
    try {
      var raw = window.localStorage.getItem(storageKey(modal, name));
      var values = raw ? JSON.parse(raw) : [];
      return new Set(Array.isArray(values) ? values : []);
    } catch (error) {
      return new Set();
    }
  }

  function writeSet(modal, name, set) {
    try {
      window.localStorage.setItem(storageKey(modal, name), JSON.stringify(Array.from(set)));
    } catch (error) {
      // Private mode or a full quota: the assistant still works in memory.
    }
  }

  function readValue(modal, name) {
    try {
      return window.localStorage.getItem(storageKey(modal, name));
    } catch (error) {
      return null;
    }
  }

  function writeValue(modal, name, value) {
    try {
      window.localStorage.setItem(storageKey(modal, name), value);
    } catch (error) {
      // See writeSet.
    }
  }

  function csrfToken() {
    var meta = document.querySelector("meta[name='csrf-token']");
    return meta ? meta.getAttribute("content") : "";
  }

  function init() {
    var modal = document.querySelector("[data-bank-wizard]");
    if (!modal || modal.dataset.bankWizardBound === "true") return;
    modal.dataset.bankWizardBound = "true";

    var panels = Array.prototype.slice.call(modal.querySelectorAll("[data-bank-wizard-panel]"));
    var navItems = Array.prototype.slice.call(modal.querySelectorAll("[data-bank-wizard-nav-item]"));
    var allNavItems = Array.prototype.slice.call(
      modal.querySelectorAll("[data-bank-wizard-nav-item], [data-testid='bank-wizard-filter-nav']")
    );
    var bankKeys = navItems.map(function (item) { return item.dataset.bankWizardGo; });
    var skipButton = modal.querySelector("[data-bank-wizard-skip]");
    var nextButton = modal.querySelector("[data-bank-wizard-next]");
    var nextLabel = modal.querySelector("[data-bank-wizard-next-label]");
    var spinner = modal.querySelector("[data-bank-wizard-spinner]");
    var progress = modal.querySelector("[data-bank-wizard-progress]");
    var progressBar = modal.querySelector("[data-bank-wizard-progress-bar]");
    var progressText = modal.querySelector("[data-bank-wizard-progress-text]");
    var content = modal.querySelector(".bank-wizard-content");

    var skipped = readSet(modal, "skipped");
    var reviewed = readSet(modal, "reviewed");
    var validKeys = panels.map(function (panel) { return panel.dataset.bankWizardPanel; });
    var storedKey = readValue(modal, "last");
    var current = validKeys.indexOf(storedKey) !== -1 ? storedKey : modal.dataset.initialKey;
    var lastBank = null;
    var saving = false;

    function panelFor(key) {
      return panels.find(function (panel) { return panel.dataset.bankWizardPanel === key; });
    }

    function navFor(key) {
      return navItems.find(function (item) { return item.dataset.bankWizardGo === key; });
    }

    function isBank(key) {
      return key !== "filters" && key !== "empty" && panelFor(key) && panelFor(key).hasAttribute("data-bank-wizard-bank");
    }

    function isConfigured(key) {
      var panel = panelFor(key);
      return !!panel && panel.dataset.bankConfigured === "true";
    }

    function stateFor(key) {
      if (skipped.has(key)) return "skipped";
      if (isConfigured(key)) return "configured";
      if (reviewed.has(key)) return "reviewed";
      if (key === current && isBank(key)) return "in_progress";
      return "pending";
    }

    function labelFor(state) {
      return {
        skipped: modal.dataset.stateSkipped,
        configured: modal.dataset.stateConfigured,
        reviewed: modal.dataset.stateReviewed,
        in_progress: modal.dataset.stateInProgress,
        pending: modal.dataset.statePending
      }[state];
    }

    function iconFor(state) {
      return {
        skipped: "ti-circle-slash",
        configured: "ti-circle-check",
        reviewed: "ti-clock",
        in_progress: "ti-progress",
        pending: "ti-circle-minus"
      }[state];
    }

    function statusClassFor(state) {
      return {
        skipped: "recognition-status-pending",
        configured: "recognition-status-ok",
        reviewed: "recognition-status-pending",
        in_progress: "recognition-status-pending",
        pending: "recognition-status-unconfigured"
      }[state];
    }

    function updateNavStates() {
      navItems.forEach(function (item, index) {
        var key = item.dataset.bankWizardGo;
        var state = stateFor(key);
        var stateEl = item.querySelector("[data-bank-wizard-nav-state]");
        var numEl = item.querySelector("[data-bank-wizard-nav-num]");
        if (stateEl) stateEl.textContent = labelFor(state);
        if (numEl) {
          var complete = state === "configured" || state === "reviewed";
          numEl.innerHTML = complete ? '<i class="ti ti-check" aria-hidden="true"></i>' : String(index + 1);
        }
        item.classList.toggle("is-active", key === current);
        if (key === current) item.setAttribute("aria-current", "step");
        else item.removeAttribute("aria-current");
      });
    }

    function updatePanel(panel) {
      var key = panel.dataset.bankWizardPanel;
      if (!isBank(key)) return;
      var state = stateFor(key);
      var status = panel.querySelector("[data-bank-wizard-status]");
      var statusText = panel.querySelector("[data-bank-wizard-status-text]");
      var counter = panel.querySelector("[data-bank-wizard-counter]");
      var index = bankKeys.indexOf(key);
      if (statusText) statusText.textContent = labelFor(state);
      if (status) {
        status.className = "recognition-status " + statusClassFor(state);
        var icon = status.querySelector("i");
        if (icon) icon.className = "ti " + iconFor(state);
        if (state === "skipped" && isConfigured(key)) {
          status.title = modal.dataset.statusSkippedHint || "";
        } else if (state === "configured") {
          status.title = modal.dataset.statusConfiguredHint || "";
        } else {
          status.removeAttribute("title");
        }
      }
      if (counter && index !== -1) {
        counter.textContent = modal.dataset.labelCounter
          .replace("%{current}", String(index + 1))
          .replace("%{total}", String(bankKeys.length));
      }
    }

    function updateProgress() {
      var total = bankKeys.length;
      var reviewedCount = bankKeys.filter(function (key) {
        return isConfigured(key) || reviewed.has(key) || skipped.has(key);
      }).length;
      if (progress) {
        progress.setAttribute("aria-valuemax", String(total));
        progress.setAttribute("aria-valuenow", String(reviewedCount));
        progress.setAttribute("aria-label", modal.dataset.labelProgress
          .replace("%{reviewed}", String(reviewedCount))
          .replace("%{total}", String(total)));
      }
      if (progressBar) progressBar.style.width = (total ? (reviewedCount * 100 / total) : 0) + "%";
      if (progressText) {
        progressText.textContent = modal.dataset.labelProgress
          .replace("%{reviewed}", String(reviewedCount))
          .replace("%{total}", String(total));
      }
    }

    function updateFooter() {
      var onFilterOrEmpty = current === "filters" || current === "empty";
      if (skipButton) skipButton.hidden = onFilterOrEmpty || bankKeys.length === 0;
      if (nextLabel) {
        nextLabel.textContent = saving
          ? modal.dataset.labelSaving
          : (onFilterOrEmpty ? modal.dataset.labelFinish : modal.dataset.labelSave);
      }
      if (nextButton) nextButton.disabled = saving;
      if (skipButton) skipButton.disabled = saving;
      if (spinner) spinner.classList.toggle("d-none", !saving);
    }

    function clearError(panel) {
      if (!panel) return;
      var error = panel.querySelector("[data-bank-wizard-error]");
      if (!error) return;
      error.hidden = true;
      error.textContent = "";
    }

    function markDirty(panel) {
      if (panel && isBank(panel.dataset.bankWizardPanel)) panel.dataset.bankDirty = "true";
    }

    function hasDirtyBanks() {
      return panels.some(function (panel) { return panel.dataset.bankDirty === "true"; });
    }

    function showError(panel, message) {
      if (!panel) return;
      var error = panel.querySelector("[data-bank-wizard-error]");
      if (!error) return;
      error.textContent = message || modal.dataset.errorGeneric;
      error.hidden = false;
      if (error.scrollIntoView) error.scrollIntoView({ block: "nearest" });
    }

    function sectionInputs(panel, section) {
      return Array.prototype.slice.call(
        panel.querySelectorAll("input[type='hidden'][name='" + section + "[]']")
      );
    }

    function addValue(panel, section) {
      if (!panel) return;
      var input = panel.querySelector("[data-bank-wizard-new-value='" + section + "']");
      var chips = panel.querySelector("[data-recognition-chips='" + section + "']");
      if (!input || !chips) return;

      var value = input.value.trim();
      if (!value) return;

      // Never store the same value twice, regardless of case.
      var duplicate = sectionInputs(panel, section).some(function (hidden) {
        return hidden.value && hidden.value.toLowerCase() === value.toLowerCase();
      });
      if (!duplicate) {
        var chip = document.createElement("span");
        chip.className = "recognition-chip";
        chip.setAttribute("data-testid", "bank-wizard-chip");
        chip.appendChild(document.createTextNode(value));

        var hidden = document.createElement("input");
        hidden.type = "hidden";
        hidden.name = section + "[]";
        hidden.value = value;
        chip.appendChild(hidden);

        var remove = document.createElement("button");
        remove.type = "button";
        remove.className = "recognition-chip-remove";
        remove.setAttribute("data-recognition-remove", "");
        remove.setAttribute("aria-label", modal.dataset.labelRemove || "Quitar");
        remove.innerHTML = '<i class="ti ti-x"></i>';
        chip.appendChild(remove);
        chips.appendChild(chip);
        markDirty(panel);
      }

      input.value = "";
      input.focus();
    }

    // A value typed but not yet added is still submitted when saving.
    function commitPendingValues(panel) {
      addValue(panel, "senders");
      addValue(panel, "subjects");
    }

    function showStep(key) {
      if (!panelFor(key)) key = modal.dataset.initialKey;
      current = key;
      if (isBank(key)) lastBank = key;
      panels.forEach(function (panel) {
        var active = panel.dataset.bankWizardPanel === current;
        panel.classList.toggle("is-active", active);
        panel.hidden = !active;
        if (active) updatePanel(panel);
      });
      navItems.forEach(function (item) {
        var active = item.dataset.bankWizardGo === current;
        item.classList.toggle("is-active", active);
        if (active) item.setAttribute("aria-current", "step");
        else item.removeAttribute("aria-current");
      });
      allNavItems.forEach(function (item) {
        if (item.hasAttribute("data-bank-wizard-nav-item")) return;
        var active = item.dataset.bankWizardGo === current;
        item.classList.toggle("is-active", active);
        if (active) item.setAttribute("aria-current", "step");
        else item.removeAttribute("aria-current");
      });
      updateNavStates();
      updateProgress();
      updateFooter();
      writeValue(modal, "last", current);
      if (content) content.scrollTop = 0;
      var bodyScroller = modal.querySelector(".bank-wizard-body");
      if (bodyScroller) bodyScroller.scrollTop = 0;
    }

    function nextStepAfter(key) {
      var index = bankKeys.indexOf(key);
      return bankKeys[index + 1] || "filters";
    }

    function finish() {
      if (!hasDirtyBanks()) {
        window.location.assign(modal.dataset.finishUrl);
        return;
      }
      Dialog.confirm(modal.dataset.unsavedMessage, { title: "Confirmar", confirmLabel: "Salir", variant: "warning" }).then(function (confirmed) {
        if (confirmed) window.location.assign(modal.dataset.finishUrl);
      });
    }

    function saveCurrent() {
      if (saving) return;
      var panel = panelFor(current);
      if (!panel) return;
      var form = panel.querySelector("[data-bank-wizard-form]");
      if (!form) return;

      clearError(panel);
      commitPendingValues(panel);
      saving = true;
      updateFooter();

      fetch(form.action, {
        method: (form.getAttribute("method") || "post").toUpperCase(),
        headers: {
          "Accept": "application/json",
          "X-CSRF-Token": csrfToken()
        },
        body: new FormData(form),
        credentials: "same-origin"
      }).then(function (response) {
        return response.json().catch(function () { return {}; }).then(function (body) {
          if (!response.ok) {
            var errors = Array.isArray(body.errors) ? body.errors.join(" ") : "";
            var failure = new Error(errors || modal.dataset.errorGeneric);
            failure.bankWizardServer = true;
            throw failure;
          }
          return body;
        });
      }).then(function (body) {
        var savedKey = current;
        panel.dataset.bankConfigured = body.configured ? "true" : "false";
        delete panel.dataset.bankDirty;
        reviewed.add(savedKey);
        skipped.delete(savedKey);
        writeSet(modal, "reviewed", reviewed);
        writeSet(modal, "skipped", skipped);
        saving = false;
        updateFooter();
        updateNavStates();
        updateProgress();
        showStep(nextStepAfter(savedKey));
      }).catch(function (error) {
        saving = false;
        updateFooter();
        var message = error && error.bankWizardServer ? error.message : modal.dataset.errorNetwork;
        showError(panel, message);
      });
    }

    function skipCurrent() {
      if (saving || !isBank(current)) return;
      skipped.add(current);
      reviewed.delete(current);
      writeSet(modal, "skipped", skipped);
      writeSet(modal, "reviewed", reviewed);
      var skippedKey = current;
      updateNavStates();
      updateProgress();
      showStep(nextStepAfter(skippedKey));
    }

    function goTo(key) {
      if (!panelFor(key)) return;
      showStep(key);
    }

    skipButton && skipButton.addEventListener("click", skipCurrent);
    nextButton && nextButton.addEventListener("click", function () {
      if (current === "filters" || current === "empty") finish();
      else saveCurrent();
    });

    modal.addEventListener("click", function (event) {
      var add = event.target.closest("[data-bank-wizard-add]");
      if (add && modal.contains(add)) {
        event.preventDefault();
        addValue(add.closest("[data-bank-wizard-panel]"), add.dataset.bankWizardAdd);
        return;
      }
      var go = event.target.closest("[data-bank-wizard-go]");
      if (go && modal.contains(go)) {
        event.preventDefault();
        goTo(go.dataset.bankWizardGo);
        return;
      }
      var back = event.target.closest("[data-bank-wizard-back]");
      if (back && modal.contains(back)) {
        event.preventDefault();
        goTo(lastBank || bankKeys[0] || "empty");
      }
    });

    modal.addEventListener("keydown", function (event) {
      if (event.key !== "Enter") return;
      var input = event.target.closest("[data-bank-wizard-new-value]");
      if (!input) return;
      event.preventDefault();
      addValue(input.closest("[data-bank-wizard-panel]"), input.dataset.bankWizardNewValue);
    });

    // Editing any chip clears the previous save error and marks the bank dirty.
    modal.addEventListener("click", function (event) {
      if (!event.target.closest("[data-recognition-remove], [data-recognition-accept-suggestion], [data-recognition-dismiss-suggestion]")) return;
      var panel = event.target.closest("[data-bank-wizard-panel]");
      markDirty(panel);
      clearError(panelFor(current));
    });
    modal.addEventListener("input", function (event) {
      markDirty(event.target.closest("[data-bank-wizard-panel]"));
      clearError(panelFor(current));
    });

    var allowHide = false;
    modal.addEventListener("hide.bs.modal", function (event) {
      if (saving) {
        event.preventDefault();
        return;
      }
      if (allowHide) {
        allowHide = false;
        return;
      }
      if (!hasDirtyBanks()) return;
      event.preventDefault();
      Dialog.confirm(modal.dataset.unsavedMessage, { title: "Confirmar", confirmLabel: "Salir", variant: "warning" }).then(function (confirmed) {
        if (confirmed) {
          allowHide = true;
          var instance = (window.bootstrap && window.bootstrap.Modal) ? window.bootstrap.Modal.getInstance(modal) : null;
          if (instance) instance.hide();
        }
      });
    });

    updateNavStates();
    updateProgress();
    updateFooter();
    showStep(current);

    if (modal.dataset.autoOpen === "true" && window.bootstrap) {
      window.bootstrap.Modal.getOrCreateInstance(modal).show();
    }
  }

  // The wizard page is server-rendered with ?wizard=1. On later opens the
  // modal already exists, so intercept the link and show it without a reload;
  // this preserves unsaved edits and the navigation state.
  document.addEventListener("click", function (event) {
    if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    var opener = event.target.closest("[data-bank-wizard-open]");
    if (!opener) return;
    var modal = document.querySelector("[data-bank-wizard]");
    if (!modal || !window.bootstrap) return;
    event.preventDefault();
    window.bootstrap.Modal.getOrCreateInstance(modal).show();
  });

  document.addEventListener("DOMContentLoaded", init);
  document.addEventListener("turbo:load", init);
})();
