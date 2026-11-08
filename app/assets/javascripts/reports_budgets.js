// Budget vs. actual report: switches between the table and the chart without
// reloading. The chart is rendered while hidden, so showing it also triggers a
// resize to give Chart.js the real container width.
(function () {
  "use strict";

  var CHART_ID = "budget-vs-actual-chart";

  function chartObject() {
    var chartkick = window.Chartkick && window.Chartkick.charts[CHART_ID];
    return chartkick && chartkick.getChartObject();
  }

  function resizeChart() {
    var chart = chartObject();
    if (chart) chart.resize();
  }

  function init() {
    var root = document.querySelector("[data-budget-report]");
    if (!root || root.dataset.budgetReportInitialized === "true") return;
    root.dataset.budgetReportInitialized = "true";

    var buttons = Array.prototype.slice.call(root.querySelectorAll("[data-budget-view]"));
    var panels = Array.prototype.slice.call(root.querySelectorAll("[data-budget-panel]"));

    function activate(view) {
      panels.forEach(function (panel) {
        panel.hidden = panel.dataset.budgetPanel !== view;
      });

      buttons.forEach(function (button) {
        var active = button.dataset.budgetView === view;
        button.classList.toggle("is-active", active);
        button.setAttribute("aria-selected", active ? "true" : "false");
        button.tabIndex = active ? 0 : -1;
      });

      if (view !== "chart") return;

      window.setTimeout(resizeChart, 60);
      window.setTimeout(resizeChart, 250);
    }

    buttons.forEach(function (button, index) {
      button.addEventListener("click", function () {
        activate(button.dataset.budgetView);
      });

      button.addEventListener("keydown", function (event) {
        if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return;

        event.preventDefault();
        var offset = event.key === "ArrowRight" ? 1 : -1;
        var next = buttons[(index + offset + buttons.length) % buttons.length];
        next.focus();
        activate(next.dataset.budgetView);
      });
    });
  }

  document.addEventListener("turbo:load", init);
  document.addEventListener("DOMContentLoaded", init);
  window.addEventListener("chartkick:load", resizeChart);
  if (document.readyState !== "loading") init();
})();
