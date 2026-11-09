// Reports: spending-trend chart interactions. Bars open the transactions
// behind their bucket, tooltips add the bucket's transaction count, and the
// average line is drawn without an extra charting dependency.
(function () {
  "use strict";

  var CHART_ID = "spending-trend-chart";
  var AVERAGE_PLUGIN_ID = "etAverageLine";
  var MAX_ATTEMPTS = 100;

  function parseJson(value, fallback) {
    try {
      return JSON.parse(value || "");
    } catch (error) {
      return fallback;
    }
  }

  function roundRect(ctx, x, y, width, height, radius) {
    ctx.beginPath();
    ctx.moveTo(x + radius, y);
    ctx.lineTo(x + width - radius, y);
    ctx.quadraticCurveTo(x + width, y, x + width, y + radius);
    ctx.lineTo(x + width, y + height - radius);
    ctx.quadraticCurveTo(x + width, y + height, x + width - radius, y + height);
    ctx.lineTo(x + radius, y + height);
    ctx.quadraticCurveTo(x, y + height, x, y + height - radius);
    ctx.lineTo(x, y + radius);
    ctx.quadraticCurveTo(x, y, x + radius, y);
    ctx.closePath();
  }

  function averageLineOptions(chart) {
    var container = chart.canvas.closest("[data-spending-trend]");
    if (!container) return null;

    var value = parseFloat(container.getAttribute("data-spending-trend-average"));
    if (!Number.isFinite(value) || value <= 0) return null;

    return {
      value: value,
      label: container.getAttribute("data-spending-trend-average-label")
    };
  }

  function drawAverageLine(chart) {
    var options = averageLineOptions(chart);
    if (!options) return;

    var scale = chart.scales.y;
    var area = chart.chartArea;
    if (!scale || !area) return;

    var y = scale.getPixelForValue(options.value);
    if (!Number.isFinite(y) || y < area.top || y > area.bottom) return;

    var ctx = chart.ctx;
    ctx.save();
    ctx.beginPath();
    ctx.setLineDash([6, 5]);
    ctx.lineWidth = 1.5;
    ctx.strokeStyle = "rgba(148, 163, 184, 0.95)";
    ctx.moveTo(area.left, y);
    ctx.lineTo(area.right, y);
    ctx.stroke();

    if (options.label) {
      var text = String(options.label);
      var padding = 5;
      ctx.setLineDash([]);
      ctx.font = '600 10px "Plus Jakarta Sans", sans-serif';

      var width = ctx.measureText(text).width;
      var boxX = area.right - width - padding * 2 - 2;
      var boxY = y - 18;
      if (boxY < area.top) boxY = y + 7;

      var card = chart.canvas.closest(".trend-chart-card");
      var cardStyle = card ? window.getComputedStyle(card) : null;
      var bodyStyle = window.getComputedStyle(document.body);

      ctx.fillStyle = (cardStyle && cardStyle.backgroundColor) || "rgba(255, 255, 255, 0.92)";
      ctx.strokeStyle = "rgba(148, 163, 184, 0.45)";
      roundRect(ctx, boxX, boxY, width + padding * 2, 16, 4);
      ctx.fill();
      ctx.stroke();

      ctx.fillStyle = bodyStyle.color || "#202d3d";
      ctx.textBaseline = "middle";
      ctx.fillText(text, boxX + padding, boxY + 8);
    }

    ctx.restore();
  }

  function registerAverageLinePlugin() {
    if (!window.Chart || window.etAverageLineRegistered) return;

    window.etAverageLineRegistered = true;
    window.Chart.register({
      id: AVERAGE_PLUGIN_ID,
      beforeInit: setupChartConfig,
      afterDatasetsDraw: drawAverageLine
    });
  }

  function openTransactionsModal(url) {
    if (window.ReportsTransactionsModal) {
      window.ReportsTransactionsModal.open(url);
    } else {
      window.location.href = url;
    }
  }

  function tooltipCallbacksFor(chart) {
    var container = chart.canvas.closest("[data-spending-trend]");
    if (!container) return null;

    var tooltips = parseJson(container.getAttribute("data-spending-trend-tooltips"), []);
    if (!tooltips.length) return null;

    return {
      label: function (context) {
        var tooltip = tooltips[context.dataIndex];
        if (!tooltip) return context.formattedValue;
        return tooltip.count ? [ tooltip.total, tooltip.count ] : tooltip.total;
      }
    };
  }

  function setupChartConfig(chart) {
    var callbacks = tooltipCallbacksFor(chart);
    if (!callbacks) return;

    var rawConfig = chart.config && chart.config._config;
    var rawOptions = rawConfig && rawConfig.options;
    if (!rawOptions) return;

    rawOptions.plugins = rawOptions.plugins || {};
    rawOptions.plugins.tooltip = rawOptions.plugins.tooltip || {};
    rawOptions.plugins.tooltip.callbacks = callbacks;
  }

  function setClickHandler(container, chart) {
    chart.canvas.style.cursor = "pointer";
  }

  function chartFor(container) {
    if (!window.Chartkick) return null;

    var chartkick = window.Chartkick.charts[CHART_ID];
    var chart = chartkick && chartkick.getChartObject();
    if (!chart || !chart.canvas) return null;
    if (!container.contains(chart.canvas)) return null;

    return chart;
  }

  function openBucketTransactions(container, event) {
    var chart = chartFor(container);
    if (!chart || event.target !== chart.canvas) return;

    var urls = parseJson(container.getAttribute("data-spending-trend-urls"), []);
    if (!urls.length) return;

    var elements = chart.getElementsAtEventForMode(event, "nearest", { intersect: true }, true);
    if (!elements.length) return;

    var url = urls[elements[0].index];
    if (url) openTransactionsModal(url);
  }

  document.addEventListener("click", function (event) {
    var container = event.target.closest && event.target.closest("[data-spending-trend]");
    if (container) openBucketTransactions(container, event);
  }, true);

  function attach(container) {
    if (container.dataset.spendingTrendBound === "true") return true;
    if (!window.Chartkick) return false;

    var chartkick = window.Chartkick.charts[CHART_ID];
    var chart = chartkick && chartkick.getChartObject();
    if (!chart || !chart.canvas) return false;

    container.dataset.spendingTrendBound = "true";
    setClickHandler(container, chart);
    return true;
  }

  function setupLoading(root) {
    if (root.dataset.spendingTrendLoadingBound === "true") return;
    root.dataset.spendingTrendLoadingBound = "true";

    function showSkeleton() {
      var skeleton = root.querySelector("[data-trend-skeleton]");
      var content = root.querySelector("[data-trend-content]");
      if (!skeleton || !content) return;

      content.hidden = true;
      skeleton.hidden = false;
      root.setAttribute("aria-busy", "true");
    }

    root.addEventListener("submit", showSkeleton);
    root.addEventListener("click", function (event) {
      if (event.target.closest("[data-report-navigation]")) showSkeleton();
    });
  }

  function init(attempt) {
    var root = document.querySelector("[data-spending-trend-page]");
    if (root) setupLoading(root);

    var container = document.querySelector("[data-spending-trend]");
    if (!container) return;

    if (attach(container)) return;
    if (attempt < MAX_ATTEMPTS) {
      window.setTimeout(function () { init(attempt + 1); }, 50);
    }
  }

  registerAverageLinePlugin();
  if (!window.etAverageLineRegistered) {
    window.addEventListener("load", registerAverageLinePlugin);
  }

  document.addEventListener("DOMContentLoaded", function () { init(0); });
  document.addEventListener("turbo:load", function () { init(0); });
  window.addEventListener("chartkick:load", function () { init(0); });
  if (document.readyState !== "loading") init(0);
})();
