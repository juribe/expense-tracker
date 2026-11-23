(function () {
  var modal = document.getElementById("forwarding-rule-wizard");
  if (!modal || modal.dataset.forwardingRuleBound === "true") return;
  modal.dataset.forwardingRuleBound = "true";

  var provider = document.getElementById("forwarding_rule_provider");
  var senders = document.getElementById("forwarding_rule_senders");
  var subjects = document.getElementById("forwarding_rule_subjects");
  var summary = document.getElementById("forwarding_rule_summary");
  var query = document.getElementById("forwarding_rule_query");

  var panels = modal.querySelectorAll("[data-forwarding-panel]");
  var navItems = modal.querySelectorAll("[data-forwarding-nav-item]");
  var nextButton = modal.querySelector("[data-forwarding-next]");
  var nextLabel = modal.querySelector("[data-forwarding-next-label]");
  var backButton = modal.querySelector("[data-forwarding-back]");
  var current = "explain";

  function panelFor(key) {
    for (var i = 0; i < panels.length; i += 1) {
      if (panels[i].getAttribute("data-forwarding-panel") === key) return panels[i];
    }
    return null;
  }

  function showStep(key) {
    if (!panelFor(key)) return;
    current = key;

    panels.forEach(function (panel) {
      var active = panel.getAttribute("data-forwarding-panel") === current;
      panel.classList.toggle("is-active", active);
      panel.hidden = !active;
    });

    navItems.forEach(function (item) {
      var active = item.getAttribute("data-forwarding-go") === current;
      item.classList.toggle("is-active", active);
      if (active) item.setAttribute("aria-current", "step");
      else item.removeAttribute("aria-current");
    });

    if (backButton) backButton.hidden = current === "explain";
    if (nextLabel) {
      nextLabel.textContent = current === "explain" ? modal.dataset.labelExplainCta : modal.dataset.labelDone;
    }
  }

  function advance() {
    if (current === "explain") showStep("rule");
    else closeWizard();
  }

  function closeWizard() {
    if (window.bootstrap && window.bootstrap.Modal) {
      window.bootstrap.Modal.getOrCreateInstance(modal).hide();
    }
  }

  function values(field) {
    return (field.value || "")
      .split(/[\n,]/)
      .map(function (value) { return value.trim(); })
      .filter(function (value) { return value.length > 0; });
  }

  function quoted(values) {
    return values.map(function (value) {
      return '"' + value.replace(/"/g, "") + '"';
    });
  }

  function updateProviderPanels() {
    var selected = provider ? provider.value : "gmail";
    modal.querySelectorAll("[data-provider-panel]").forEach(function (panel) {
      panel.hidden = panel.getAttribute("data-provider-panel") !== selected;
    });
  }

  function updateQuery() {
    if (!query) return;
    var parts = [];
    var from = values(senders);
    if (from.length) parts.push("from:(" + from.join(" OR ") + ")");

    var subjectValues = values(subjects);
    if (subjectValues.length) parts.push("subject:(" + quoted(subjectValues).join(" OR ") + ")");

    query.textContent = parts.length ? parts.join(" ") : modal.dataset.emptyQuery;
  }

  function updateSummary() {
    if (!summary) return;
    var from = values(senders);
    var subjectValues = values(subjects);
    summary.textContent =
      (modal.dataset.labelSenders || "Remitentes") + ": " + (from.length ? from.join(", ") : "—") +
      " · " + (modal.dataset.labelSubjects || "Asuntos") + ": " +
      (subjectValues.length ? subjectValues.join(", ") : modal.dataset.anySubject);
  }

  function copyText(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(text);
    }
    var helper = document.createElement("textarea");
    helper.value = text;
    helper.setAttribute("readonly", "readonly");
    helper.style.position = "fixed";
    helper.style.opacity = "0";
    document.body.appendChild(helper);
    helper.select();
    document.execCommand("copy");
    helper.remove();
    return Promise.resolve();
  }

  function copyButton(button) {
    var target = document.querySelector(button.getAttribute("data-copy-target"));
    if (!target) return;
    var text = "value" in target ? target.value : target.textContent;
    copyText(text || "").then(function () {
      var original = button.innerHTML;
      button.innerHTML = '<i class="ti ti-check me-1" aria-hidden="true"></i>' + modal.dataset.copied;
      window.setTimeout(function () { button.innerHTML = original; }, 1500);
    });
  }

  modal.addEventListener("click", function (event) {
    var go = event.target.closest("[data-forwarding-go]");
    if (go && modal.contains(go)) {
      event.preventDefault();
      showStep(go.getAttribute("data-forwarding-go"));
      return;
    }

    var copy = event.target.closest("[data-copy-target]");
    if (copy && modal.contains(copy)) copyButton(copy);
  });

  nextButton && nextButton.addEventListener("click", advance);
  backButton && backButton.addEventListener("click", function () { showStep("explain"); });

  senders && senders.addEventListener("input", function () { updateQuery(); updateSummary(); });
  subjects && subjects.addEventListener("input", function () { updateQuery(); updateSummary(); });
  provider && provider.addEventListener("change", function () {
    updateProviderPanels();
    updateQuery();
    updateSummary();
  });

  modal.addEventListener("hidden.bs.modal", function () { showStep("explain"); });

  showStep("explain");
  updateProviderPanels();
  updateQuery();
  updateSummary();
})();
