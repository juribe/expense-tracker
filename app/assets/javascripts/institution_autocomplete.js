(function () {
  // --- institution autocomplete ---------------------------------------------
  // Searchable combobox for the money-source institution selector
  // ([data-institution-combobox] in money_sources/_institution_select).
  // The option list travels inline as JSON in data-options (catalog +
  // user's custom entities); the chosen polymorphic ref lives in the hidden
  // money_source[institution_ref] input and is parsed server-side by
  // MoneySource#assign_institution_ref. Vanilla, no frameworks.
  var INSTITUTION_MAX_SUGGESTIONS = 12;

  function institutionFold(text) {
    return String(text == null ? "" : text)
      .normalize("NFKD")
      .replace(/\p{Mn}/gu, "")
      .toLowerCase();
  }

  function institutionHiddenInput(combobox) {
    var cell = combobox.closest(".mb-3") || combobox.parentElement;
    return cell ? cell.querySelector("input[type=hidden][name*='institution_ref']") : null;
  }

  function institutionExhaustiveData(combobox) {
    if (!combobox.dataset.optionsParsed) {
      combobox.dataset.optionsParsed = "true";
      try {
        combobox._data = JSON.parse(combobox.dataset.options || "{}");
      } catch (e) {
        combobox._data = {};
      }
    }
    return combobox._data || {};
  }

  function institutionOptions(combobox) {
    var data = institutionExhaustiveData(combobox);
    return data.options || [];
  }

  function institutionMatchesSearch(option, query) {
    if (String(query || "").trim() === "") return true;

    var needle = institutionFold(query);
    return institutionFold(option.label).indexOf(needle) !== -1 ||
           institutionFold(option.type).indexOf(needle) !== -1;
  }

  function institutionLabelFor(combobox, ref) {
    var options = institutionOptions(combobox);
    for (var i = 0; i < options.length; i++) {
      if (options[i].value === ref) return options[i].label;
    }
    return null;
  }

  function institutionItemHtml(data, option, highlighted) {
    var group = data.groups && data.groups[option.group];
    var badge = "";
    if (option.type && data.types && data.types[option.type]) {
      badge = '<span class="badge bg-light text-dark border ms-1">' +
        escapeInstitutionHtml(data.types[option.type]) + "</span>";
    }
    if (option.inactive) {
      badge += ' <span class="badge bg-secondary-subtle text-secondary-emphasis">' +
        escapeInstitutionHtml(data.inactive_marker || "") + "</span>";
    }
    var prefix = group ? '<span class="text-secondary small">' +
      escapeInstitutionHtml(group) + " · </span>" : "";

    var classes = "dropdown-item" + (highlighted ? " active" : "") +
      (option.inactive ? " text-secondary" : "");
    return '<button type="button" class="' + classes + '" data-institution-option value="' +
      escapeInstitutionHtml(option.value) + '">' + prefix +
      escapeInstitutionHtml(option.label) + badge + "</button>";
  }

  // Minimal escaper: labels originate from user-given names, so never trust
  // them inside innerHTML.
  function escapeInstitutionHtml(text) {
    return String(text == null ? "" : text).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  // Recreates the dropdown body from the JSON data: the "no entity" entry
  // first, then group headers (catalog / custom entities) and highlighted
  // option navigation state.
  function institutionRenderList(combobox, query) {
    var data = institutionExhaustiveData(combobox);
    var list = combobox.querySelector("[data-institution-list]");
    var options = institutionOptions(combobox);
    var chosen = combobox.dataset.selectedRef || "";

    var html = '<button type="button" class="dropdown-item text-secondary' +
      (chosen === "" ? " active" : "") + '" data-institution-option value="">';
    html += escapeInstitutionHtml(data.none_label || "—") + "</button>";

    var lastGroup = null;
    var allowed = options.filter(function (option) { return institutionMatchesSearch(option, query); })
                         .slice(0, INSTITUTION_MAX_SUGGESTIONS);
    allowed.forEach(function (option) {
      if (option.group !== lastGroup) {
        lastGroup = option.group;
        var heading = data.groups && data.groups[lastGroup];
        html += '<h6 class="dropdown-header">' + escapeInstitutionHtml(heading || "") + "</h6>";
      }
      html += institutionItemHtml(data, option, option.value === chosen);
    });
    if (allowed.length === 0) {
      html += '<span class="dropdown-item text-secondary disabled">' +
        escapeInstitutionHtml(data.no_match || "—") + "</span>";
    }

    list.innerHTML = html;
    list.hidden = false;
    list.classList.add("show");
    combobox.querySelector("[data-institution-search]").setAttribute("aria-expanded", "true");
    combobox.dataset.highlightIndex = -1;
  }

  function institutionCloseList(combobox) {
    var list = combobox.querySelector("[data-institution-list]");
    list.hidden = true;
    list.classList.remove("show");
    combobox.querySelector("[data-institution-search]").setAttribute("aria-expanded", "false");
    combobox.dataset.highlightIndex = -1;
  }

  // Read-only snapshot: shows the stored selection in the text input and the
  // clear button. Kept consistent by this module only.
  function institutionSyncDisplay(combobox) {
    var hidden = institutionHiddenInput(combobox);
    var search = combobox.querySelector("[data-institution-search]");
    var clear = combobox.querySelector("[data-institution-clear]");
    var ref = hidden ? hidden.value : "";
    var data = institutionExhaustiveData(combobox);

    combobox.dataset.selectedRef = ref;
    search.value = ref ? (institutionLabelFor(combobox, ref) || "") : "";
    clear.hidden = ref === "";
    combobox.dataset.highlightIndex = -1;
    void data; // parsed lazily on first interaction
  }

  function institutionPick(combobox, value) {
    var hidden = institutionHiddenInput(combobox);
    var search = combobox.querySelector("[data-institution-search]");
    var clear = combobox.querySelector("[data-institution-clear]");

    if (hidden) hidden.value = value;
    combobox.dataset.selectedRef = value;
    search.value = value === "" ? "" : (institutionLabelFor(combobox, value) || "");
    clear.hidden = value === "";
    institutionCloseList(combobox);
    search.focus();
  }

  function institutionHighlightedItem(combobox) {
    var items = combobox.querySelectorAll("[data-institution-option]");
    var index = parseInt(combobox.dataset.highlightIndex || "-1", 10);
    return items[index] || null;
  }

  function institutionMoveHighlight(combobox, delta) {
    var items = combobox.querySelectorAll("[data-institution-option]");
    var index = Math.max(parseInt(combobox.dataset.highlightIndex || "-1", 10) + delta, -1);
    if (index > items.length - 1) index = items.length - 1;
    if (index < 0) index = 0;
    combobox.dataset.highlightIndex = String(index);
    items.forEach(function (item, i) { item.classList.toggle("active", i === index); });
    return items[index];
  }

  function institutionBind(scope) {
    scope.querySelectorAll("[data-institution-combobox]").forEach(function (combobox) {
      institutionSyncDisplay(combobox);
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    institutionBind(document);
  });

  // Delegated interactions (the comboboxes may be re-rendered inside panels).
  document.addEventListener("focusin", function (e) {
    var combobox = e.target.closest("[data-institution-combobox]");
    if (combobox && e.target.matches("[data-institution-search]")) {
      institutionRenderList(combobox, "");
    }
  });

  document.addEventListener("input", function (e) {
    var combobox = e.target.closest("[data-institution-combobox]");
    if (combobox && e.target.matches("[data-institution-search]")) {
      institutionRenderList(combobox, e.target.value);
    }
  });

  document.addEventListener("keydown", function (e) {
    var combobox = e.target.closest("[data-institution-combobox]");
    if (!combobox || !e.target.matches("[data-institution-search]")) return;
    var list = combobox.querySelector("[data-institution-list]");
    if (list.hidden) return;

    if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      institutionMoveHighlight(combobox, e.key === "ArrowDown" ? 1 : -1);
    } else if (e.key === "Enter") {
      var highlighted = institutionHighlightedItem(combobox);
      if (highlighted) {
        e.preventDefault();
        institutionPick(combobox, highlighted.getAttribute("value"));
      }
    } else if (e.key === "Escape") {
      institutionCloseList(combobox);
    }
  });

  document.addEventListener("mousedown", function (e) {
    var item = e.target.closest("[data-institution-option]");
    if (!item) return;
    e.preventDefault();
    var combobox = item.closest("[data-institution-combobox]");
    institutionPick(combobox, item.getAttribute("value"));
  });

  document.addEventListener("click", function (e) {
    var clearButton = e.target.closest("[data-institution-clear]");
    if (clearButton) {
      var combobox = clearButton.closest("[data-institution-combobox]");
      institutionPick(combobox, "");
      return;
    }
    // Clicking anywhere outside the combobox closes its open list.
    document.querySelectorAll("[data-institution-combobox]").forEach(function (combobox) {
      if (!combobox.contains(e.target) &&
          !combobox.querySelector("[data-institution-list]").hidden) {
        // A pending typed query is discarded: the hidden input already holds
        // the committed selection (or none).
        institutionCloseList(combobox);
      }
    });
  });
})();
