(function () {
  // ---------------------------------------------------------------- Source recognition chips
  function recognitionChipsContainer(chipsEl) { return chipsEl; }
  function recognitionCountEl(chipsEl) {
    var section = chipsEl.closest(".recognition-section");
    return section && section.querySelector("[data-recognition-count]");
  }
  function recognitionKind(chipsEl) { return chipsEl.getAttribute("data-recognition-chips"); }
  function recognitionFieldName(kind) { return kind + "[]"; }
  function recognitionRefreshCount(chipsEl) {
    var countEl = recognitionCountEl(chipsEl);
    if (!countEl) return;
    var chips = chipsEl.querySelectorAll(".recognition-chip").length;
    countEl.textContent = countEl.textContent.replace(/\d+/, String(chips));
  }

  function recognitionMakeChip(value, kind) {
    var chip = document.createElement("span");
    chip.className = "recognition-chip";
    chip.setAttribute("data-testid", "recognition-chip");

    var hidden = document.createElement("input");
    hidden.type = "hidden";
    hidden.name = recognitionFieldName(kind);
    hidden.value = value;

    var remove = document.createElement("button");
    remove.type = "button";
    remove.className = "recognition-chip-remove";
    remove.setAttribute("data-recognition-remove", "");
    remove.setAttribute("aria-label", "Remover");
    remove.innerHTML = '<i class="ti ti-x"></i>';

    chip.appendChild(document.createTextNode(value));
    chip.appendChild(hidden);
    chip.appendChild(remove);
    return chip;
  }

  function recognitionSetupAddInput(chipAddBtn) {
    var chipsEl = chipAddBtn.closest("[data-recognition-chips]");
    if (!chipsEl || chipAddBtn.dataset.recognitionBound === "true") return;
    chipAddBtn.dataset.recognitionBound = "true";
    var kind = recognitionKind(chipsEl);

    chipAddBtn.addEventListener("click", function () {
      if (chipsEl.querySelector(".recognition-inline-add")) return;
      var input = document.createElement("input");
      input.type = "text";
      input.className = "form-control form-control-sm recognition-inline-add";
      input.setAttribute("data-recognition-inline-add", kind);
      input.placeholder = "...";
      chipAddBtn.parentNode.insertBefore(input, chipAddBtn);
      input.focus();

      // Enter commit and the blur that removing the input triggers must
      // never both add the chip: one value, one chip.
      var committed = false;
      function commit() {
        if (committed) return;
        committed = true;
        var value = input.value.trim();
        if (value) {
          chipsEl.insertBefore(recognitionMakeChip(value, kind), chipAddBtn);
          recognitionRefreshCount(chipsEl);
          recognitionMarkDirty();
        }
        input.value = "";
        input.remove();
      }
      input.addEventListener("keydown", function (e) { if (e.key === "Enter") { e.preventDefault(); commit(); } });
      input.addEventListener("blur", commit);
    });
  }

  function recognitionAcceptChip(suggestedChip, panel) {
    var chipsEl = panel.querySelector("[data-recognition-chips='" + suggestedChip.dataset.suggestedFor + "']");
    if (!chipsEl) return;
    var value = suggestedChip.dataset.suggestedValue || "";
    var kind = suggestedChip.dataset.suggestedFor;
    var existing = chipsEl.querySelectorAll('input[name="' + recognitionFieldName(kind) + '"]');
    for (var i = 0; i < existing.length; i++) {
      if (existing[i].value === value) return;
    }
    chipsEl.insertBefore(recognitionMakeChip(value, kind), chipsEl.querySelector(".recognition-chip-add"));
    recognitionRefreshCount(chipsEl);
  }

  function recognitionDismissChip(suggestedChip, form) {
    if (!form) return;
    var hidden = document.createElement("input");
    hidden.type = "hidden";
    hidden.name = "dismissed[" + suggestedChip.dataset.suggestedFor + "][]";
    hidden.value = suggestedChip.dataset.suggestedValue || "";
    form.appendChild(hidden);
  }

  // --- drawer dirty tracking -------------------------------------------------
  function recognitionForm() { return document.querySelector("form.recognition-form"); }
  function recognitionMarkDirty() {
    var form = recognitionForm();
    if (form) form.dataset.recognitionDirty = "true";
  }
  function recognitionIsDirty() {
    var form = recognitionForm();
    return !!form && form.dataset.recognitionDirty === "true";
  }
  function recognitionLeaveUrl() {
    var overlay = document.querySelector(".recognition-drawer-overlay");
    if (overlay && overlay.dataset.closeUrl) return overlay.dataset.closeUrl;
    var cancel = document.querySelector(".recognition-drawer-foot [data-recognition-close]");
    return cancel ? cancel.getAttribute("href") : window.location.pathname;
  }
  // Delegate: pick up any chips rendered on the page (also after form edits).
  document.addEventListener("click", function (e) {
    var closer = e.target.closest("[data-recognition-close]");
    if (closer) {
      if (!recognitionIsDirty()) {
        showRecognitionVeil(closer);
        if (closer.tagName !== "A") {
          e.preventDefault();
          var cleanUrl = closer.dataset.closeUrl || recognitionLeaveUrl();
          if (window.Turbo) { window.Turbo.visit(cleanUrl); } else { window.location.href = cleanUrl; }
        }
        return;
      }
      e.preventDefault();
      var form = recognitionForm();
      var message = (form && form.dataset.unsavedMessage) || "Are you sure?";
      Dialog.confirm(message, { title: "Confirmar", confirmLabel: "Salir", variant: "warning" }).then(function (confirmed) {
        if (!confirmed) return;
        showRecognitionVeil(closer);
        var dirtyUrl = closer.dataset.closeUrl || recognitionLeaveUrl();
        if (window.Turbo) { window.Turbo.visit(dirtyUrl); } else { window.location.href = dirtyUrl; }
      });
      return;
    }
    var remove = e.target.closest("[data-recognition-remove]");
    if (remove) {
      var chipsEl = remove.closest("[data-recognition-chips]");
      remove.closest(".recognition-chip").remove();
      if (chipsEl) recognitionRefreshCount(chipsEl);
      recognitionMarkDirty();
      return;
    }
    var focusBtn = e.target.closest("[data-recognition-accept-suggestion]");
    if (focusBtn) {
      var chip = focusBtn.closest(".recognition-chip-suggested");
      // The manual drawer and the bank wizard both use the same chip markup;
      // scope the acceptance to the section that owns the suggestion.
      var panel = focusBtn.closest("[data-recognition-panel], .recognition-drawer");
      if (chip && panel) recognitionAcceptChip(chip, panel);
      if (chip) chip.remove();
      recognitionMarkDirty();
      return;
    }
    var dismissBtn = e.target.closest("[data-recognition-dismiss-suggestion]");
    if (dismissBtn) {
      var suggested = dismissBtn.closest(".recognition-chip-suggested");
      // Dismissals belong to the enclosing form (wizard bank form or drawer).
      if (suggested) recognitionDismissChip(suggested, suggested.closest("form") || recognitionForm());
      if (suggested) suggested.remove();
      recognitionMarkDirty();
      return;
    }
  });

  document.addEventListener("submit", function (e) {
    var form = e.target.closest("form.recognition-form");
    if (form && !e.defaultPrevented) {
      delete form.dataset.recognitionDirty;
      showRecognitionSaveLoading(e.submitter || form.querySelector("[data-testid='recognition-save']"));
    }
  });

  document.addEventListener("keydown", function (e) {
    if (e.key !== "Escape" || !document.querySelector(".recognition-drawer")) return;
    if (!recognitionIsDirty()) {
      showRecognitionVeil();
      var cleanUrl = recognitionLeaveUrl();
      if (window.Turbo) { window.Turbo.visit(cleanUrl); } else { window.location.href = cleanUrl; }
      return;
    }
    var form = recognitionForm();
    var message = (form && form.dataset.unsavedMessage) || "Are you sure?";
    Dialog.confirm(message, { title: "Confirmar", confirmLabel: "Salir", variant: "warning" }).then(function (confirmed) {
      if (!confirmed) return;
      showRecognitionVeil();
      var dirtyUrl = recognitionLeaveUrl();
      if (window.Turbo) { window.Turbo.visit(dirtyUrl); } else { window.location.href = dirtyUrl; }
    });
  });

  window.addEventListener("beforeunload", function (e) {
    if (!recognitionIsDirty()) return;
    e.preventDefault();
    e.returnValue = "";
  });

  function bindRecognition(scope) {
    scope.querySelectorAll("[data-recognition-chips] .recognition-chip-add").forEach(recognitionSetupAddInput);
  }

  // --- drawer navigation feedback ---------------------------------------------
  // Opening (edit/bank-edit links) and closing (data-recognition-close) the
  // drawer are full Turbo re-renders: while the request is in flight nothing
  // moved on screen and it read as lag. A full-screen veil with a spinner
  // shows instantly on click and hides when the next render lands.
  function showRecognitionVeil(link) {
    var veil = document.createElement("div");
    veil.className = "turbo-veil";
    veil.innerHTML = '<div class="turbo-veil-card"><span class="spinner-border" aria-hidden="true"></span></div>';
    if (link) veil.dataset.fromLink = link.getAttribute("data-testid") || "";
    document.body.classList.add("turbo-loading");
    document.body.appendChild(veil);
  }

  function hideRecognitionVeil() {
    document.body.classList.remove("turbo-loading");
    document.querySelectorAll(".turbo-veil").forEach(function (veil) { veil.remove(); });
    document.querySelectorAll("[data-testid='edit-recognition'].is-loading, [data-testid='recognition-bank-edit'].is-loading")
            .forEach(function (link) { link.classList.remove("is-loading"); });
    document.querySelectorAll("form.recognition-form [data-testid='recognition-save']")
            .forEach(resetRecognitionSave);
  }

  function resetRecognitionSave(button) {
    if (!button) return;
    button.disabled = false;
    button.removeAttribute("aria-busy");
    button.classList.remove("is-loading");
  }

  function showRecognitionSaveLoading(button) {
    if (!button || button.disabled) return;
    button.disabled = true;
    button.setAttribute("aria-busy", "true");
    button.classList.add("is-loading");
    showRecognitionVeil();
  }

  // Clicked drawer-open links: flag it and lift the veil BEFORE Turbo navigates.
  document.addEventListener("click", function (e) {
    var link = e.target.closest("a[data-testid='edit-recognition'], a[data-testid='recognition-bank-edit']");
    if (!link) return;
    if (link.classList.contains("is-loading")) { e.preventDefault(); return; }
    link.classList.add("is-loading");
    showRecognitionVeil(link);
  }, true);

  // Render landed (or someone left a stale veil behind): clean slate.
  document.addEventListener("turbo:load", hideRecognitionVeil);
  document.addEventListener("turbo:before-cache", hideRecognitionVeil);
  document.addEventListener("turbo:fetch-request-error", hideRecognitionVeil);
  document.addEventListener("DOMContentLoaded", hideRecognitionVeil);
  window.addEventListener("pageshow", hideRecognitionVeil);

  // --- collapsible recognition cards ------------------------------------------
  // Bank group cards and the Gmail criteria card are collapsed accordions:
  // any [data-recognition-toggle] inside a [data-recognition-collapsible]
  // flips the card's `expanded` class (bodies are server-rendered and only
  // hidden with CSS, so the content stays crawler/test friendly).
  function recognitionToggleCard(card) {
    var expanded = card.classList.toggle("expanded");
    card.querySelectorAll("[data-recognition-toggle]").forEach(function (btn) {
      btn.setAttribute("aria-expanded", expanded ? "true" : "false");
    });
  }

  document.addEventListener("click", function (e) {
    var toggle = e.target.closest("[data-recognition-toggle]");
    if (!toggle) return;
    var card = toggle.closest("[data-recognition-collapsible]");
    if (!card) return;
    e.preventDefault();
    recognitionToggleCard(card);
  });

  document.addEventListener("DOMContentLoaded", function () {
    bindRecognition(document);
  });

  // --- guided recognition tutorial -------------------------------------------
  // The "¿Cómo funciona?" modal holds five server-rendered step panels: the
  // active one is switched with local state (`.is-active`), the progress rail
  // is clickable and the last step swaps "Next" for "Back to start".
  function recognitionHelpShow(modal, targetStep) {
    var steps = Array.prototype.slice.call(modal.querySelectorAll("[data-testid='recognition-help-step']"));
    var current = steps.findIndex(function (step) { return step.classList.contains("is-active"); });
    var index = Math.max(0, Math.min(targetStep - 1, steps.length - 1));
    if (index === current) return;

    var last = index === steps.length - 1;
    steps.forEach(function (step, i) {
      var active = i === index;
      step.classList.toggle("is-active", active);
      step.setAttribute("data-help-active", active ? "true" : "false");
    });
    modal.querySelectorAll("[data-testid='help-progress-step']").forEach(function (dot, i) {
      dot.classList.toggle("is-active", i === index);
      dot.classList.toggle("is-done", i < index);
    });
    var readoutTitle = modal.querySelector("[data-help-title]");
    var readoutMeta = modal.querySelector("[data-help-meta]");
    var stepTitle = steps[index].getAttribute("data-help-title-text");
    if (readoutTitle && stepTitle) readoutTitle.textContent = stepTitle;
    if (readoutMeta) {
      var template = readoutMeta.dataset.progressTemplate || "";
      readoutMeta.textContent = template.replace("%{count}", index + 1).replace("%{total}", steps.length);
    }
    var prev = modal.querySelector("[data-testid='help-prev']");
    var next = modal.querySelector("[data-testid='help-next']");
    var restart = modal.querySelector("[data-testid='help-restart']");
    if (prev) prev.disabled = index === 0;
    if (restart) restart.classList.toggle("d-none", !last);
    if (next) next.classList.toggle("d-none", last);
    var body = modal.querySelector(".modal-body");
    if (body) body.scrollTop = 0;
  }

  function bindRecognitionHelp(modal) {
    if (modal.dataset.helpBound === "true") return;
    modal.dataset.helpBound = "true";
    var readoutMeta = modal.querySelector("[data-help-meta]");
    if (readoutMeta) readoutMeta.dataset.progressTemplate = readoutMeta.textContent;
    var restart = modal.querySelector("[data-testid='help-restart']");
    if (restart) restart.classList.add("d-none");

    modal.addEventListener("click", function (e) {
      var steps = modal.querySelectorAll("[data-testid='recognition-help-step']");
      var current = -1;
      for (var i = 0; i < steps.length; i++) {
        if (steps[i].classList.contains("is-active")) { current = i; break; }
      }

      var jump = e.target.closest("[data-help-jump]");
      if (jump) { recognitionHelpShow(modal, parseInt(jump.dataset.helpJump, 10)); return; }

      var nav = e.target.closest("[data-help-nav]");
      if (!nav) return;
      if (nav.dataset.helpNav === "prev") recognitionHelpShow(modal, current);
      if (nav.dataset.helpNav === "next") recognitionHelpShow(modal, current + 2);
      if (nav.dataset.helpNav === "restart") recognitionHelpShow(modal, 1);
    });
  }

  // Re-run the assistant every time the modal opens (Bootstrap event).
  document.addEventListener("shown.bs.modal", function (e) {
    var el = document.getElementById("recognition-help-modal");
    if (el && el === e.target) {
      recognitionHelpShow(el, 1);
      bindRecognitionHelp(el);
    }
  });

  document.addEventListener("DOMContentLoaded", function () {
    var el = document.getElementById("recognition-help-modal");
    if (el) bindRecognitionHelp(el);
  });

  document.addEventListener("turbo:load", function () {
    var el = document.getElementById("recognition-help-modal");
    if (el) bindRecognitionHelp(el);
  });

})();
