// Client-side search and status filters for the automatic rules index.
//
// Both controls combine to hide cards inside the existing grid; no request is
// made and the current rule data stays untouched. The selected filter and the
// search text are kept in sessionStorage so toggling a rule (which reloads the
// page) does not reset the user's view.
(function () {
  var STORAGE_KEY = "yogasto.transactionRules.filters";

  function normalize(value) {
    return String(value == null ? "" : value)
      .toLowerCase()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "");
  }

  function readState() {
    try {
      return JSON.parse(sessionStorage.getItem(STORAGE_KEY)) || {};
    } catch (error) {
      return {};
    }
  }

  function saveState(state) {
    try {
      sessionStorage.setItem(STORAGE_KEY, JSON.stringify(state));
    } catch (error) {
      // Private browsing or a full quota must not break the filters.
    }
  }

  function initializeRulesIndex() {
    var grid = document.querySelector("[data-rules-grid]");
    if (!grid || grid.dataset.rulesInitialized === "true") return;
    grid.dataset.rulesInitialized = "true";

    var searchInput = document.querySelector("[data-rules-search]");
    var filterButtons = Array.from(document.querySelectorAll("[data-rules-filter]"));
    var cards = Array.from(document.querySelectorAll("[data-testid='rule-card']"));
    var noResults = document.querySelector("[data-testid='rules-no-results']");
    var clearButton = document.querySelector("[data-rules-clear]");
    var state = readState();
    var allowedFilters = [ "all", "enabled", "disabled" ];
    var activeFilter = allowedFilters.indexOf(state.filter) === -1 ? "all" : state.filter;

    function persist() {
      saveState({
        query: searchInput ? searchInput.value : "",
        filter: activeFilter
      });
    }

    function applyFilters() {
      var query = normalize(searchInput ? searchInput.value.trim() : "");
      var visibleCount = 0;

      cards.forEach(function (card) {
        var enabled = card.dataset.ruleEnabled === "true";
        var statusMatches =
          activeFilter === "all" ||
          (activeFilter === "enabled" && enabled) ||
          (activeFilter === "disabled" && !enabled);
        var textMatches = query === "" || normalize(card.dataset.ruleSearch).indexOf(query) !== -1;
        var visible = statusMatches && textMatches;

        card.hidden = !visible;
        if (visible) visibleCount += 1;
      });

      if (noResults) noResults.hidden = visibleCount !== 0;
    }

    function selectFilter(filter) {
      activeFilter = filter;

      filterButtons.forEach(function (button) {
        var selected = button.dataset.rulesFilter === filter;
        button.classList.toggle("active", selected);
        button.setAttribute("aria-pressed", selected ? "true" : "false");
      });

      applyFilters();
    }

    if (searchInput && typeof state.query === "string") {
      searchInput.value = state.query;
    }

    filterButtons.forEach(function (button) {
      button.addEventListener("click", function () {
        selectFilter(button.dataset.rulesFilter);
        persist();
      });
    });

    if (searchInput) {
      searchInput.addEventListener("input", function () {
        applyFilters();
        persist();
      });
    }

    if (clearButton) {
      clearButton.addEventListener("click", function () {
        if (searchInput) searchInput.value = "";
        selectFilter("all");
        persist();
        if (searchInput) searchInput.focus();
      });
    }

    selectFilter(activeFilter);
  }

  document.addEventListener("DOMContentLoaded", initializeRulesIndex);
  document.addEventListener("turbo:load", initializeRulesIndex);
  if (document.readyState !== "loading") initializeRulesIndex();
})();
