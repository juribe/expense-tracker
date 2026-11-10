// Búsqueda y filtros visuales de la sección Categorías.
//
// Trabaja sobre las tarjetas ya renderizadas por el servidor: no consulta ni
// reclasifica categorías, solo oculta las que no coinciden dentro de la
// pestaña activa (gastos o ingresos).
(function () {
  var ACTIVE_CLASS = "active";

  function initializeCategoryIndex() {
    var search = document.querySelector("[data-category-search]");
    if (!search || search.dataset.categoryIndexBound === "true") return;
    search.dataset.categoryIndexBound = "true";

    var filters = Array.prototype.slice.call(document.querySelectorAll("[data-category-filter]"));
    var groups = Array.prototype.slice.call(document.querySelectorAll("[data-category-group]"));
    var noResults = document.querySelector("[data-category-no-results]");
    var activeFilter = "all";

    function normalize(value) {
      return (value || "").trim().toLocaleLowerCase("es");
    }

    function matches(card, query, filter) {
      var matchesName = !query || normalize(card.dataset.categoryName).indexOf(query) !== -1;
      var matchesFilter = filter === "all" || card.dataset.categoryKind === filter;
      return matchesName && matchesFilter;
    }

    function updateCount(group, visible) {
      var counter = group.querySelector("[data-category-count]");
      if (counter) counter.textContent = visible;
    }

    function apply() {
      var query = normalize(search.value);
      var filtering = query.length > 0 || activeFilter !== "all";
      var totalVisible = 0;
      var visibleGroups = 0;

      groups.forEach(function (group) {
        var cards = Array.prototype.slice.call(group.querySelectorAll("[data-category-card]"));
        var visible = 0;

        cards.forEach(function (card) {
          var show = matches(card, query, activeFilter);
          card.hidden = !show;
          if (show) visible += 1;
        });

        totalVisible += visible;
        updateCount(group, visible);

        var empty = group.querySelector("[data-category-empty]");
        var showEmptyState = cards.length === 0 && query.length === 0 &&
          (activeFilter === "all" || activeFilter === group.dataset.categoryGroup);

        group.hidden = cards.length > 0 ? visible === 0 : !showEmptyState;
        if (empty) empty.hidden = !showEmptyState;
        if (!group.hidden) visibleGroups += 1;
      });

      if (noResults) noResults.hidden = !(filtering && totalVisible === 0 && visibleGroups === 0);
    }

    filters.forEach(function (button) {
      button.addEventListener("click", function () {
        activeFilter = button.dataset.categoryFilter || "all";
        filters.forEach(function (other) {
          var selected = other === button;
          other.classList.toggle(ACTIVE_CLASS, selected);
          other.setAttribute("aria-pressed", selected ? "true" : "false");
        });
        apply();
      });
    });

    search.addEventListener("input", apply);
    apply();
  }

  document.addEventListener("turbo:load", initializeCategoryIndex);
  document.addEventListener("DOMContentLoaded", initializeCategoryIndex);
  if (document.readyState !== "loading") initializeCategoryIndex();
})();
