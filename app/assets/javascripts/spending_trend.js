// Reports: make spending-trend bars open the transactions behind their bucket.
// Chartkick exposes each chart through Chartkick.charts[id], and the view
// provides one drill-down URL per bucket in data-spending-trend-urls.
(function () {
  var CHART_ID = "spending-trend-chart";
  var MAX_ATTEMPTS = 100;

  function drillDownUrls(container) {
    try {
      return JSON.parse(container.getAttribute("data-spending-trend-urls") || "[]");
    } catch (error) {
      return [];
    }
  }

  function openTransactionsModal(url) {
    if (window.ReportsTransactionsModal) {
      window.ReportsTransactionsModal.open(url);
    } else {
      window.location.href = url;
    }
  }

  function attach(container) {
    if (container.dataset.spendingTrendBound === "true") return true;

    var urls = drillDownUrls(container);
    if (!urls.length || !window.Chartkick) return false;

    var chartkick = window.Chartkick.charts[CHART_ID];
    var chart = chartkick && chartkick.getChartObject();
    if (!chart || !chart.canvas) return false;

    container.dataset.spendingTrendBound = "true";
    chart.canvas.style.cursor = "pointer";
    chart.canvas.addEventListener("click", function (event) {
      var elements = chart.getElementsAtEventForMode(event, "nearest", { intersect: true }, true);
      if (!elements.length) return;

      var url = urls[elements[0].index];
      if (url) openTransactionsModal(url);
    });
    return true;
  }

  function init(attempt) {
    var container = document.querySelector("[data-spending-trend]");
    if (!container) return;

    if (attach(container)) return;
    if (attempt < MAX_ATTEMPTS) {
      window.setTimeout(function () { init(attempt + 1); }, 50);
    }
  }

  document.addEventListener("DOMContentLoaded", function () { init(0); });
  window.addEventListener("chartkick:load", function () { init(0); });
})();
