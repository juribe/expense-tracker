// Client-side search, potential filters and sorting for the category
// savings-opportunity list. Data is rendered by Rails; this module only
// reorders and hides rows, so no financial calculation happens here.

(function () {
  "use strict";

  function normalize(value) {
    return (value || "").toString().toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
  }

  function potentialRank(value) {
    var ranks = { high: 0, medium: 1, low: 2 };
    return ranks[value] === undefined ? 3 : ranks[value];
  }

  function init() {
    var root = document.querySelector("[data-category-insights]");
    if (!root || root.dataset.categoryInsightsInitialized === "true") return;
    root.dataset.categoryInsightsInitialized = "true";

    var list = root.querySelector("[data-category-insights-list]");
    if (!list) return;

    var items = Array.prototype.slice.call(root.querySelectorAll("[data-category-insights-item]"));
    var search = root.querySelector("[data-category-insights-search]");
    var sort = root.querySelector("[data-category-insights-sort]");
    var tabs = Array.prototype.slice.call(root.querySelectorAll("[data-category-insights-filter]"));
    var empty = root.querySelector("[data-category-insights-empty]");
    var count = root.querySelector("[data-category-insights-count]");
    var state = { filter: "all", query: "", sort: "default" };

    function sorted(rows) {
      return rows.slice().sort(function (a, b) {
        var nameA = a.dataset.categoryName || "";
        var nameB = b.dataset.categoryName || "";
        var amountA = parseFloat(a.dataset.currentSpending || "0");
        var amountB = parseFloat(b.dataset.currentSpending || "0");

        if (state.sort === "alpha") return nameA.localeCompare(nameB, "es");
        if (state.sort === "amount") return amountB - amountA || nameA.localeCompare(nameB, "es");
        if (state.sort === "potential") {
          return potentialRank(a.dataset.potential) - potentialRank(b.dataset.potential) ||
            amountB - amountA || nameA.localeCompare(nameB, "es");
        }
        return Number(a.dataset.defaultIndex || 0) - Number(b.dataset.defaultIndex || 0);
      });
    }

    function apply() {
      var visible = items.filter(function (item) {
        var matchesFilter = state.filter === "all" || item.dataset.potential === state.filter;
        var matchesQuery = normalize(item.dataset.categoryName).indexOf(normalize(state.query)) !== -1;
        return matchesFilter && matchesQuery;
      });

      items.forEach(function (item) { item.hidden = true; });
      sorted(visible).forEach(function (item) {
        item.hidden = false;
        list.appendChild(item);
      });

      if (empty) empty.hidden = visible.length > 0;
      if (count) count.textContent = String(visible.length);
    }

    items.forEach(function (item) {
      item.addEventListener("click", function (event) {
        if (event.target.closest("a, button")) return;
        var link = item.querySelector("[data-category-insights-link]");
        if (link) link.click();
      });
    });

    tabs.forEach(function (tab) {
      tab.addEventListener("click", function () {
        state.filter = tab.dataset.categoryInsightsFilter || "all";
        tabs.forEach(function (other) {
          var active = other === tab;
          other.classList.toggle("is-active", active);
          other.setAttribute("aria-pressed", active ? "true" : "false");
        });
        apply();
      });
    });

    if (search) {
      search.addEventListener("input", function () {
        state.query = search.value;
        apply();
      });
    }

    if (sort) {
      sort.addEventListener("change", function () {
        state.sort = sort.value;
        apply();
      });
    }

    apply();
  }

  document.addEventListener("turbo:load", init);
  document.addEventListener("DOMContentLoaded", init);
  if (document.readyState !== "loading") init();
})();
