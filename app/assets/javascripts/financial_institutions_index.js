// Búsqueda de "Mis entidades".
//
// Trabaja sobre las tarjetas ya renderizadas por el servidor: no consulta ni
// reclasifica entidades, solo oculta las que no coinciden por nombre. Los
// tipos y las acciones siguen siendo los datos reales de cada entidad.
(function () {
  function initializeFinancialInstitutionsIndex() {
    var search = document.querySelector("[data-financial-institution-search]");
    if (!search || search.dataset.financialInstitutionsIndexBound === "true") return;
    search.dataset.financialInstitutionsIndexBound = "true";

    var cards = Array.prototype.slice.call(
      document.querySelectorAll("[data-financial-institution-card]")
    );
    var noResults = document.querySelector("[data-financial-institutions-no-results]");

    function normalize(value) {
      return (value || "").trim().toLocaleLowerCase("es");
    }

    function apply() {
      var query = normalize(search.value);
      var visible = 0;

      cards.forEach(function (card) {
        var show = !query || normalize(card.dataset.entityName).indexOf(query) !== -1;
        card.hidden = !show;
        if (show) visible += 1;
      });

      if (noResults) noResults.hidden = !(query && cards.length > 0 && visible === 0);
    }

    search.addEventListener("input", apply);
    apply();
  }

  document.addEventListener("turbo:load", initializeFinancialInstitutionsIndex);
  document.addEventListener("DOMContentLoaded", initializeFinancialInstitutionsIndex);
  if (document.readyState !== "loading") initializeFinancialInstitutionsIndex();
})();
