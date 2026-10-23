(function() {
  var payloadEl = document.querySelector("[data-evaluations-payload]");
  var CATEGORIES = payloadEl ? JSON.parse(payloadEl.dataset.evaluationsPayload).categories : [];

  function csrfToken() {
    return (document.querySelector('meta[name="csrf-token"]') || {}).content || "";
  }

  function money(value) {
    var n = Number(value);
    if (!isFinite(n)) n = 0;
    return "$" + n.toLocaleString("en-US", { minimumFractionDigits: 0, maximumFractionDigits: 2 });
  }

  function escapeHtml(text) {
    var div = document.createElement("div");
    div.textContent = text == null ? "" : String(text);
    return div.innerHTML;
  }

  var EVAL_FIELDS = ["intent", "amount", "date", "activity", "category", "subcategory", "money_source", "currency"];
  var evalPollTimer = null;
  var evalCurrentId = null;
  var EVALUATIONS_URL = "/expense-evaluations";

  function evalPatch(url, options) {
    options = options || {};
    options.headers = Object.assign({ "Accept": "application/json", "X-CSRF-Token": csrfToken() }, options.headers || {});
    options.credentials = "same-origin";
    return fetch(url, options).then(function (response) {
      return response.json().then(function (data) {
        if (typeof data === "object" && data !== null && data.ok === false) throw new Error((data.errors || []).join(" "));
        return data;
      });
    });
  }

  function setEvalStatusBadge(status) {
    var badge = $("#pgEvalRunStatus");
    var map = {
      pending: ["bg-warning-subtle text-warning", "Pendiente"],
      running: ["bg-info-subtle text-info", "En progreso"],
      completed: ["bg-success-subtle text-success", "Completada"],
      failed: ["bg-danger-subtle text-danger", "Fallida"]
    };
    var entry = map[status] || ["bg-secondary-subtle text-secondary", status];
    badge.className = "badge " + entry[0] + " ms-2";
    badge.textContent = entry[1];
  }

  function $(sel) { return document.querySelector(sel); }

  function renderEvaluationRun(data) {
    var run = data.run;
    var metrics = run.metrics || {};
    var m = function (key) { return metrics[key]; };
    evalCurrentId = run.id;

    $("#pgEvalResults").classList.remove("d-none");
    setEvalStatusBadge(run.status);
    $("#pgEvalRunProgress").style.width = Math.round(Number(run.progress) * 100) + "%";
    $("#pgEvalRunMeta").textContent =
      (run.started_at ? "Iniciada: " + new Date(run.started_at).toLocaleString() + " · " : "") +
      (run.completed_at ? "Completada: " + new Date(run.completed_at).toLocaleString() : "");
    $("#pgEvalRunCaption").textContent =
      [run.dataset_name, [run.provider, run.model].filter(Boolean).join("/") || run.model,
       run.prompt_version].filter(Boolean).join(" · ");

    $("#pgEvalTotal").textContent = run.total_cases;
    $("#pgEvalPassed").textContent = m("passed_cases") != null ? m("passed_cases") : "—";
    $("#pgEvalFailed").textContent = m("failed_cases") != null ? m("failed_cases") : "—";
    $("#pgEvalJsonValid").textContent = m("json_validity") != null ? Math.round(Number(m("json_validity")) * 100) + "%" : "—";
    $("#pgEvalCost").textContent = m("total_cost") != null ? money(m("total_cost")) : "—";
    $("#pgEvalLatency").textContent = m("average_latency") != null ? Number(m("average_latency")).toFixed(2) + "s" : "—";

    var fa = $("#pgEvalFieldAccuracy");
    fa.textContent = "";
    var fieldAccuracy = m("field_accuracy") || {};
    var compared = Object.keys(metrics.fields || {}).reduce(function (sum, field) {
      return sum + (Number(metrics.fields[field].compared) || 0);
    }, 0);
    EVAL_FIELDS.forEach(function (field, idx) {
      var acc = Number(fieldAccuracy[field]);
      var pct = isNaN(acc) ? 0 : Math.round(acc * 100);
      var line = document.createElement("div");
      line.className = (idx ? "mt-2 " : "") + "d-flex justify-content-between align-items-center gap-2";
      line.innerHTML =
        '<span class="text-capitalize text-muted">' + field + "</span>" +
        '<div class="progress flex-grow-1" style="height:6px"><div class="progress-bar" style="width:' + pct + '%"></div></div>' +
        '<span class="text-muted">' + (compared && compared > 0 ? String(pct) + "%" : "—") + "</span>";
      fa.appendChild(line);
    });
    var frAcc = Number(m("full_record_accuracy"));
    var frPct = isNaN(frAcc) ? 0 : Math.round(frAcc * 100);
    var fr = document.createElement("div");
    fr.className = "mt-3 fw-semibold";
    fr.innerHTML = "Full Record (todos los campos) " +
      '<div class="progress" style="height:6px"><div class="progress-bar" style="width:' + frPct + '%"></div></div>' +
      '<span class="fw-normal text-muted">' + (compared && compared > 0 ? String(frPct) + "%" : "—") + "</span>";
    fa.appendChild(fr);

    renderEvaluateCompare(run.dataset_name);
    loadFailedCases(run.id);

    if (run.status === "running" || run.status === "pending") {
      evalPollTimer = setTimeout(function () { pollEvaluation(run.id); }, 2000);
    } else {
      evalPollTimer = null;
    }
  }

  function pollEvaluation(id) {
    evalPatch(EVALUATIONS_URL + "/" + id).then(renderEvaluationRun).catch(function () {
      evalPollTimer = setTimeout(function () { pollEvaluation(id); }, 3000);
    });
  }

  function startEvaluation(dataset, filename) {
    var btn = $("#pgEvalStartBtn");
    var provider = $("#pgEvalProvider").value;
    var model = $("#pgEvalModel").value.trim();
    var forceNew = $("#pgEvalForceNew").checked;
    var error = $("#pgEvalError");
    error.classList.add("d-none");

    if (!model) {
      error.textContent = "Indica un modelo.";
      error.classList.remove("d-none");
      return;
    }

    btn.disabled = true;
    btn.innerHTML = '<span class="spinner-border spinner-border-sm me-1"></span>Iniciando…';

    evalPatch(EVALUATIONS_URL + "/start", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ dataset: dataset, filename: filename, provider: provider, model: model, force_new: forceNew })
    }).then(function (data) {
      if (evalPollTimer) { clearTimeout(evalPollTimer); evalPollTimer = null; }
      $("#pgEvalResults").classList.remove("d-none");
      loadEvaluationHistory();
      pollEvaluation(data.run.id);
    }).catch(function (err) {
      error.textContent = err.message || "No se pudo iniciar la evaluación.";
      error.classList.remove("d-none");
    }).finally(function () {
      btn.disabled = false;
      btn.innerHTML = '<i class="ti ti-player-play me-1"></i>Ejecutar Evaluación';
    });
  }

  function renderEvaluateCompare(datasetName) {
    fetch(EVALUATIONS_URL + (datasetName ? "?dataset=" + encodeURIComponent(datasetName) : ""), {
      headers: { "Accept": "application/json", "X-CSRF-Token": csrfToken() }
    }).then(function (response) { return response.json(); }).then(function (data) {
      var runs = (data.runs || []).filter(function (r) { return r.status === "completed"; });
      var body = $("#pgEvalCompareBody");
      body.textContent = "";
      runs.forEach(function (r) {
        var mets = r.metrics || {};
        var acc = Number(mets.full_record_accuracy != null ? mets.full_record_accuracy : mets.accuracy);
        var tr = document.createElement("tr");
        tr.innerHTML =
          "<td>" + escapeHtml(r.model || "—") + "</td>" +
          "<td>" + escapeHtml(isNaN(acc) ? "—" : Math.round(acc * 100) + "%") + "</td>" +
          "<td>" + escapeHtml(mets.json_validity != null ? Math.round(Number(mets.json_validity) * 100) + "%" : "—") + "</td>" +
          "<td>" + escapeHtml(mets.average_latency != null ? Number(mets.average_latency).toFixed(1) + "s" : "—") + "</td>" +
          "<td>" + escapeHtml(mets.total_cost != null ? money(mets.total_cost) : "—") + "</td>";
        body.appendChild(tr);
      });
    }).catch(function () { /* compare stays empty */ });
  }

  function loadEvaluationHistory() {
    evalPatch(EVALUATIONS_URL).then(function (data) {
      var runs = data.runs || [];
      var body = $("#pgEvalHistoryBody");
      body.textContent = "";
      runs.forEach(function (r) {
        var statusMap = {
          pending: ["bg-warning-subtle text-warning", "Pendiente"],
          running: ["bg-info-subtle text-info", "En progreso"],
          completed: ["bg-success-subtle text-success", "Completada"],
          failed: ["bg-danger-subtle text-danger", "Fallida"]
        };
        var st = statusMap[r.status] || ["bg-secondary-subtle text-secondary", r.status];
        var mets = r.metrics || {};
        var acc = Number(mets.full_record_accuracy != null ? mets.full_record_accuracy : mets.accuracy);
        var tr = document.createElement("tr");
        tr.setAttribute("data-testid", "evaluation-history-row");
        tr.style.cursor = "pointer";
        tr.addEventListener("click", function () {
          if (evalPollTimer) { clearTimeout(evalPollTimer); evalPollTimer = null; }
          $("#pgEvalResults").classList.remove("d-none");
          pollEvaluation(r.id);
        });
        tr.innerHTML =
          "<td class=\"small\">" + escapeHtml(r.dataset_name || "—") + "</td>" +
          "<td class=\"small text-muted\">" + escapeHtml(r.model || "—") + "</td>" +
          '<td><span class="badge ' + st[0] + '">' + st[1] + "</span></td>" +
          "<td class=\"small text-muted text-end\">" +
          (isNaN(acc) ? "" : Math.round(acc * 100) + "%") +
          (r.status === "running" ? " " + Math.round(Number(r.progress) * 100) + "%" : "") +
          "</td>";
        body.appendChild(tr);
      });
      $("#pgEvalHistoryEmpty").classList.toggle("d-none", runs.length > 0);
    }).catch(function () { /* history stays empty */ });
  }

  function prettyValue(value) {
    if (value == null || value === "") return "—";
    if (typeof value === "object") {
      try { return JSON.stringify(value); } catch (e) { return String(value); }
    }
    return String(value);
  }

  function fieldDetailRow(fr, c) {
    var actual = prettyValue(fr.actual);
    if (fr.field === "category" && c.suggested_category &&
        actual.toLowerCase().indexOf(c.suggested_category.toLowerCase()) === -1) {
      actual += ' <span class="badge bg-warning text-dark">→ ' + escapeHtml(c.suggested_category) + "</span>";
    }
    return "<tr>" +
      "<td class=\"small fw-semibold\">" + escapeHtml(fr.field) + "</td>" +
      "<td class=\"small\"><span class=\"badge bg-success-subtle text-success\">" + escapeHtml(prettyValue(fr.expected)) + "</span></td>" +
      "<td class=\"small\"><span class=\"badge bg-danger-subtle text-danger\">" + actual + "</span></td>" +
      "</tr>";
  }

  function mappingControls(c) {
    if (c.mapped) return '<span class="badge bg-success">✓ Mapeado a categoría existente</span>';
    var options = CATEGORIES.map(function (cat) {
      return '<option value="' + cat.id + '">' + escapeHtml(cat.name) + "</option>";
    }).join("");
    return '<div class="d-flex flex-wrap align-items-center gap-2">' +
      '<button type="button" class="btn btn-sm btn-outline-success btn-map" data-map-action="accept_received">Aceptar asignación</button>' +
      '<span class="text-muted">o</span>' +
      '<select class="form-select form-select-sm pg-exist" style="width:auto" title="Usar categoría existente">' +
      '<option value="">Usar categoría existente…</option>' + options + "</select>" +
      '<button type="button" class="btn btn-sm btn-outline-primary btn-map" data-map-action="use_existing">Usar</button>' +
      '<span class="text-muted">o</span>' +
      '<input type="text" class="form-control form-control-sm pg-new" style="width:auto" placeholder="Nueva categoría…">' +
      '<button type="button" class="btn btn-sm btn-outline-dark btn-map" data-map-action="create">Crear</button>' +
      "</div>";
  }

  function renderFailedCases(data) {
    var cases = data.cases || [];
    var body = $("#pgEvalFailedBody");
    body.textContent = "";
    var summary = $("#pgEvalFailedSummary");
    summary.textContent = "";
    var folds = {};
    cases.forEach(function (c) {
      if (c.suggested_category) {
        var received = (c.actual_json && c.actual_json.category) || "?";
        folds[received] = folds[received] || { target: c.suggested_category, n: 0 };
        folds[received].n += 1;
      }
      var failedFields = (c.field_results || [])
        .filter(function (fr) { return fr.compared === true && fr.matched === false; })
        .map(function (fr) { return fr.field; });
      var fieldBadges = failedFields.map(function (f) {
        return '<span class="badge bg-danger">' + escapeHtml(f) + "</span>";
      }).join(" ");
      var detailRows = (c.field_results || [])
        .filter(function (fr) { return fr.compared === true && fr.matched === false; })
        .map(function (fr) { return fieldDetailRow(fr, c); }).join("");
      var detailHtml = '<div class="p-3 bg-light rounded">' +
        '<table class="table table-sm align-middle mb-3"><thead>' +
        "<tr><th>Campo</th><th>Esperado</th><th>Recibido</th></tr></thead><tbody>" +
        (detailRows || '<tr><td colspan="3" class="small text-muted">Sin campos comparados que mostrar.</td></tr>') +
        "</tbody></table>" +
        '<div class="pg-map-cell">' + mappingControls(c) + "</div>" +
        "</div>";
      var tr = document.createElement("tr");
      tr.setAttribute("data-testid", "evaluation-failed-case");
      tr.setAttribute("data-case-id", c.id);
      tr.innerHTML =
        "<td>" +
        '<button type="button" class="btn btn-sm btn-link p-0 text-decoration-none fw-semibold pg-toggle" title="Revisar esperado vs. recibido">' +
        c.row_number + ' <i class="ti ti-chevron-down"></i></button>' +
        "</td>" +
        "<td class=\"small\">" + escapeHtml(c.message) + "</td>" +
        "<td class=\"small\">" + escapeHtml(prettyValue(c.expected_json)) + "</td>" +
        "<td class=\"small\">" + escapeHtml(prettyValue(c.actual_json || c.error)) + "</td>" +
        "<td>" + (fieldBadges || '<span class="badge bg-secondary">' + escapeHtml(c.status || "") + "</span>") + "</td>" +
        "<td class=\"small\">" + (c.latency_ms != null ? Number(c.latency_ms).toFixed(0) + "ms" : "—") + "</td>" +
        "<td class=\"small\">" + (c.input_tokens != null ? c.input_tokens + "/" + c.output_tokens : "—") + "</td>" +
        "<td class=\"small\">" + (c.cost != null ? money(c.cost) : "—") + "</td>";
      body.appendChild(tr);
      if (detailRows) {
        var detailTr = document.createElement("tr");
        detailTr.className = "d-none pg-detail";
        detailTr.innerHTML = '<td colspan="8">' + detailHtml + "</td>";
        body.appendChild(detailTr);
      }
    });

    Object.keys(folds).forEach(function (received) {
      var pill = document.createElement("span");
      pill.className = "badge bg-warning text-dark text-wrap";
      pill.textContent = folds[received].n + '× "' + received + '" → "' + folds[received].target + '"';
      summary.appendChild(pill);
    });
    summary.classList.toggle("d-none", Object.keys(folds).length === 0);

    $("#pgEvalFailedCount").textContent = data.total != null ? data.total : cases.length;
    $("#pgEvalFailedWrap").classList.remove("d-none");
    var hint = $("#pgEvalFailedHint");
    hint.classList.toggle("d-none", cases.length === 0);
    $("#pgEvalFailedEmpty").classList.toggle("d-none", cases.length > 0);
  }

  function mappingPayload(tr, action) {
    var payload = { mapping_action: action };
    if (action === "use_existing") {
      var select = tr.querySelector(".pg-exist");
      payload.category_id = select && select.value ? Number(select.value) : null;
      if (!payload.category_id) throw new Error("Selecciona una categoría existente.");
    } else if (action === "create") {
      var input = tr.querySelector(".pg-new");
      payload.new_category_name = (input && input.value || "").trim();
      if (!payload.new_category_name) throw new Error("Escribe el nombre de la nueva categoría.");
    }
    return payload;
  }

  $("#pgEvalFailedWrap").addEventListener("click", function (event) {
    var toggle = event.target.closest(".pg-toggle");
    if (toggle) {
      var detail = toggle.closest("tr").nextElementSibling;
      if (detail) detail.classList.toggle("d-none");
      return;
    }
    var btn = event.target.closest("[data-map-action]");
    if (!btn) return;
    var tr = btn.closest("[data-case-id]");
    if (!tr) return;
    var payload;
    try {
      payload = mappingPayload(tr, btn.getAttribute("data-map-action"));
    } catch (error) {
      alert(error.message);
      return;
    }
    btn.disabled = true;
    btn.textContent = "Guardando…";
    evalPatch(EVALUATIONS_URL + "/" + evalCurrentId + "/cases/" + tr.getAttribute("data-case-id") + "/mapping", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload)
    }).then(function () {
      var cell = tr.querySelector(".pg-map-cell");
      if (cell) cell.innerHTML = '<span class="badge bg-success">✓ Mapeado a categoría existente</span>';
      tr.setAttribute("data-mapped", "true");
    }).catch(function () {
      btn.disabled = false;
      btn.textContent = btn.getAttribute("data-map-action") === "accept_received" ? "Aceptar asignación"
        : (btn.getAttribute("data-map-action") === "use_existing" ? "Usar" : "Crear");
      alert("No se pudo guardar el mapeo.");
    });
  });

  function loadFailedCases(id) {
    var params = new URLSearchParams();
    var status = $("#pgEvalFailedStatus").value;
    var q = $("#pgEvalFailedQuery").value.trim();
    if (status && status !== "all") params.set("status", status);
    if (q) params.set("q", q);
    evalPatch(EVALUATIONS_URL + "/" + id + "/cases" + (params.toString() ? "?" + params.toString() : ""))
      .then(renderFailedCases)
      .catch(function () { /* failed list stays empty */ });
  }

  $("#pgEvalForm").addEventListener("submit", function (event) {
    event.preventDefault();
    var file = $("#pgEvalDatasetFile").files[0];
    var error = $("#pgEvalError");
    error.classList.add("d-none");
    if (!file) {
      error.textContent = "Selecciona un archivo CSV.";
      error.classList.remove("d-none");
      return;
    }
    var reader = new FileReader();
    reader.onerror = function () {
      error.textContent = "No se pudo leer el archivo.";
      error.classList.remove("d-none");
    };
    reader.onload = function () {
      var filename = $("#pgEvalFilename").value.trim() || file.name;
      startEvaluation(reader.result, filename);
    };
    reader.readAsText(file);
  });

  $("#pgEvalFailedRefresh").addEventListener("click", function () {
    if (evalCurrentId) loadFailedCases(evalCurrentId);
  });
  $("#pgEvalFailedQuery").addEventListener("keydown", function (event) {
    if (event.key === "Enter" && evalCurrentId) loadFailedCases(evalCurrentId);
  });
  $("#pgEvalFailedStatus").addEventListener("change", function () {
    if (evalCurrentId) loadFailedCases(evalCurrentId);
  });

  $("#pgEvalDatasetFile").addEventListener("change", function () {
    var file = this.files && this.files[0];
    var meta = $("#pgEvalDatasetMeta");
    if (!file) { meta.textContent = ""; return; }
    if (file.name) $("#pgEvalFilename").value = file.name;
    meta.textContent = file.name + " (" + file.size + " bytes) · ";
  });

  // Initialize
  loadEvaluationHistory();
})();
