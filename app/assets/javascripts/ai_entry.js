function initializeAiEntry() {
  // Listeners are bound to whatever DOM is present at run time and this block
  // deliberately has no one-shot window guard: if client-side navigation
  // (e.g. Turbo) is ever introduced, the script will simply re-run against
  // the fresh elements instead of silently leaving every button dead.

  var payloadEl = document.querySelector("[data-ai-entry-payload]");
  var P = payloadEl ? JSON.parse(payloadEl.dataset.aiEntryPayload) : { texts: {} };
  var CATEGORIES = P.categories || [];
  var MONEY_SOURCES = P.money_sources || [];
  var T = P.texts || {};

  var $ = function (sel) { return document.querySelector(sel); };

  var form = $("#aiParseForm");
  if (!form || form.dataset.aiInitialized === "true") return;
  form.dataset.aiInitialized = "true";
  var textarea = $("#aiExpenseText");
  var micButton = $("#aiMicButton");
  var statusEl = $("#aiStatus");
  var transcriptionWrap = $("#aiTranscriptionWrap");
  var transcriptionText = $("#aiTranscriptionText");
  var modalEl = $("#aiPreviewModal");
  var rowsEl = $("#aiPreviewRows");
  var totalEl = $("#aiPreviewTotal");
  var badgeEl = $("#aiDetectedBadge");
  var errorEl = $("#aiPreviewError");

  // Example chips only fill the textarea. Detection stays on the regular
  // submit button so the user always confirms before calling the AI.
  Array.prototype.forEach.call(document.querySelectorAll("[data-ai-example]"), function (button) {
    if (button.dataset.exampleBound === "true") return;
    button.dataset.exampleBound = "true";
    button.addEventListener("click", function () {
      textarea.value = button.dataset.aiExample || "";
      textarea.focus();
    });
  });

  function csrfToken() {
    var meta = document.querySelector('meta[name="csrf-token"]');
    return meta ? meta.content : "";
  }

  function setStatus(message) {
    statusEl.textContent = message || "";
  }

  function detectedCountMessage(count) {
    return count === 1
      ? T.detected_count_one
      : T.detected_count_many;
  }

  function money(value) {
    var n = Number(value);
    if (!isFinite(n)) n = 0;
    return "$" + n.toLocaleString("es-CO", { minimumFractionDigits: 0, maximumFractionDigits: 2 });
  }

  function todayISO() {
    return form.dataset.today || new Date().toISOString().slice(0, 10);
  }

  // ------------------------------------------------------------------ parsing

  function parseExpenses() {
    var text = textarea.value.trim();
    if (!text) {
      setStatus(T.write_first);
      textarea.focus();
      return;
    }

    var button = $("#aiParseButton");
    button.disabled = true;
    setStatus(T.detecting);

    fetch(form.dataset.parseUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": csrfToken()
      },
      body: JSON.stringify({ text: text })
    }).then(function (response) {
      return response.json().then(function (data) {
        return { ok: response.ok, data: data };
      });
    }).then(function (result) {
      button.disabled = false;
      if (!result.ok || !result.data.expenses || !result.data.expenses.length) {
        setStatus("");
        var message = (result.data.errors && result.data.errors[0]) || T.no_expenses;
        Dialog.alert(message, { title: "Aviso", variant: "danger" });
        return;
      }
      setStatus(detectedCountMessage(result.data.expenses.length));
      renderPreview(result.data.expenses);
      bootstrap.Modal.getOrCreateInstance(modalEl).show();
    }).catch(function () {
      button.disabled = false;
      setStatus(T.detect_failed);
    });
  }

  // ------------------------------------------------------------------ preview

  function option(value, label, selected) {
    var opt = document.createElement("option");
    opt.value = value;
    opt.textContent = label;
    opt.selected = !!selected;
    return opt;
  }

  function buildSelect(expense) {
    var select = document.createElement("select");
    select.className = "form-select form-select-sm ai-field-category";
    select.setAttribute("aria-label", T.common_category);

    var matched = null;
    if (expense.category_id) {
      matched = CATEGORIES.filter(function (c) { return String(c.id) === String(expense.category_id); })[0];
    }

    CATEGORIES.forEach(function (category) {
      select.appendChild(option(category.id, category.name, !!(matched && matched.id === category.id)));
    });

    if (!matched && expense.category_name) {
      select.appendChild(option("new:" + expense.category_name,
        T.new_category.replace("__NAME__", expense.category_name), true));
    }
    return select;
  }

  function buildSourceSelect(expense) {
    var select = document.createElement("select");
    select.className = "form-select form-select-sm ai-field-source";
    select.setAttribute("aria-label", T.ai_source);

    select.appendChild(option("", T.common_none));
    MONEY_SOURCES.forEach(function (source) {
      select.appendChild(option(source.id, source.name, !!(expense.money_source_id && String(expense.money_source_id) === String(source.id))));
    });

    return select;
  }

  function labeledField(labelText, field, className) {
    var wrapper = document.createElement("div");
    wrapper.className = className;
    var label = document.createElement("label");
    label.className = "form-label small mb-1";
    label.textContent = labelText;
    wrapper.appendChild(label);
    wrapper.appendChild(field);
    return wrapper;
  }

  function buildRow(expense) {
    expense = expense || {};
    var row = document.createElement("div");
    row.className = "ai-expense-row";
    row.setAttribute("data-testid", "ai-row");
    if (expense.low_confidence) row.classList.add("is-uncertain");

    var head = document.createElement("div");
    head.className = "ai-row-head";

    var number = document.createElement("span");
    number.className = "ai-row-number";
    number.setAttribute("aria-hidden", "true");
    head.appendChild(number);

    var badge = document.createElement("span");
    badge.className = "ai-row-badge";
    badge.innerHTML = '<i class="ti ti-stars" aria-hidden="true"></i>';
    badge.appendChild(document.createTextNode(T.ai_detected_by || "Detectado por IA"));
    head.appendChild(badge);

    var remove = document.createElement("button");
    remove.type = "button";
    remove.className = "ai-remove";
    remove.innerHTML = '<i class="ti ti-trash" aria-hidden="true"></i>';
    remove.setAttribute("aria-label", T.ai_remove_expense);
    head.appendChild(remove);

    row.appendChild(head);

    var body = document.createElement("div");
    body.className = "ai-row-body";

    if ((expense.warnings && expense.warnings.length) || expense.low_confidence) {
      var warning = document.createElement("div");
      warning.className = "ai-row-note";
      warning.setAttribute("role", "alert");
      warning.textContent = "⚠️ " + ((expense.warnings && expense.warnings.join(" ")) ||
        T.uncertain);
      body.appendChild(warning);
    }

    var grid = document.createElement("div");
    grid.className = "ai-row-fields";

    var description = document.createElement("input");
    description.type = "text";
    description.className = "form-control ai-field-description";
    description.value = expense.description || "";
    description.setAttribute("aria-label", T.common_description);
    grid.appendChild(labeledField(T.common_description, description, "ai-field ai-field-description-wrap"));

    var categorySelect = buildSelect(expense);
    grid.appendChild(labeledField(T.common_category, categorySelect, "ai-field ai-field-category-wrap"));
    // Only a user change marks the category as explicit; the parser's guess
    // stays overridable by transaction rules at save time.
    categorySelect.addEventListener("change", function () {
      row.setAttribute("data-category-edited", "true");
    });

    var amount = document.createElement("input");
    amount.type = "number";
    amount.min = "0";
    amount.step = "any";
    amount.className = "form-control ai-field-amount";
    amount.value = expense.amount != null ? expense.amount : "";
    amount.setAttribute("aria-label", T.common_amount);
    grid.appendChild(labeledField(T.common_amount, amount, "ai-field"));

    var dateField = document.createElement("input");
    dateField.type = "date";
    dateField.className = "form-control ai-field-date";
    dateField.value = expense.transaction_date || todayISO();
    dateField.setAttribute("aria-label", T.common_date);
    grid.appendChild(labeledField(T.common_date, dateField, "ai-field"));

    if (MONEY_SOURCES.length > 0) {
      grid.appendChild(labeledField(T.ai_source, buildSourceSelect(expense), "ai-field ai-field-source-wrap"));
    }

    body.appendChild(grid);
    row.appendChild(body);

    amount.addEventListener("input", updateTotal);
    remove.addEventListener("click", function () {
      row.remove();
      updateTotal();
      if (!rowsEl.querySelector(".ai-expense-row")) hideModal();
    });
    return row;
  }

  function renderPreview(expenses) {
    rowsEl.textContent = "";
    errorEl.classList.add("d-none");
    expenses.forEach(function (expense) {
      rowsEl.appendChild(buildRow(expense));
    });
    updateTotal();
  }

  function updateTotal() {
    var rows = rowsEl.querySelectorAll(".ai-expense-row");
    var total = 0;
    Array.prototype.forEach.call(rows, function (row) {
      total += Number(row.querySelector(".ai-field-amount").value) || 0;
    });
    totalEl.textContent = "Total: " + money(total);

    if (badgeEl) {
      var message = rows.length === 1 ? T.found_count_one : T.found_count_many;
      badgeEl.innerHTML = '<i class="ti ti-stars" aria-hidden="true"></i>';
      badgeEl.appendChild(document.createTextNode(message));
    }
  }

  function showModalError(message) {
    errorEl.textContent = message;
    errorEl.classList.remove("d-none");
  }

  function hideModal() {
    var instance = bootstrap.Modal.getInstance(modalEl);
    if (instance) instance.hide();
  }

  function collectExpenses() {
    var invalid = [];
    var expenses = [];
    Array.prototype.forEach.call(rowsEl.querySelectorAll(".ai-expense-row"), function (row, index) {
      var amountValue = row.querySelector(".ai-field-amount").value;
      var category = row.querySelector(".ai-field-category").value;
      var isNewCategory = category.indexOf("new:") === 0;
      var entry = {
        description: row.querySelector(".ai-field-description").value,
        amount: amountValue,
        transaction_date: row.querySelector(".ai-field-date").value,
        category_id: isNewCategory ? "" : category,
        new_category_name: isNewCategory ? category.slice(4) : "",
        category_edited: row.getAttribute("data-category-edited") === "true",
        money_source_id: row.querySelector(".ai-field-source") ? row.querySelector(".ai-field-source").value : ""
      };
      if (!amountValue || Number(amountValue) <= 0 || (!isNewCategory && !category)) {
        invalid.push(index + 1);
      }
      expenses.push(entry);
    });
    return { expenses: expenses, invalid: invalid };
  }

  function saveExpenses() {
    var collected = collectExpenses();
    if (!collected.expenses.length) return;

    if (collected.invalid.length) {
      showModalError("Revisa el/los gasto(s) " + collected.invalid.join(", ") +
        ": necesitan un monto mayor que cero y una categoría válida.");
      return;
    }

    var saveButton = $("#aiSaveAll");
    saveButton.disabled = true;

    fetch(form.dataset.bulkCreateUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": csrfToken()
      },
      body: JSON.stringify({ expenses: collected.expenses })
    }).then(function (response) {
      return response.json().then(function (data) {
        return { ok: response.ok, data: data };
      });
    }).then(function (result) {
      saveButton.disabled = false;
      if (result.ok) {
        window.location.href = result.data.redirect_to || (T.expenses_path || "/expenses");
      } else {
        showModalError((result.data.errors && result.data.errors[0]) ||
          "Los gastos no se pudieron guardar. Por favor revísalos.");
      }
    }).catch(function () {
      saveButton.disabled = false;
      showModalError("No se pudieron guardar los gastos. Inténtalo de nuevo.");
    });
  }

  // -------------------------------------------------------------------- voice

  function initVoice() {
    var SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SpeechRecognition) {
      micButton.disabled = true;
      micButton.title = "Tu navegador no admite entrada de voz.";
      return;
    }

    var recognition = new SpeechRecognition();
    var recording = false;
    var sawVoiceError = false;
    recognition.lang = "es-CO";
    recognition.interimResults = true;
    recognition.maxAlternatives = 1;

    function setRecordingUI(active) {
      recording = active;
      micButton.classList.toggle("btn-danger", active);
      micButton.classList.toggle("btn-outline-secondary", !active);
      micButton.innerHTML = active
        ? '<i class="ti ti-player-stop" aria-hidden="true"></i> Detener'
        : '<i class="ti ti-microphone" aria-hidden="true"></i> Dictar';
    }

    var VOICE_ERRORS = {
      "not-allowed": "Se denegó el acceso al micrófono. Permite el permiso del micrófono para este sitio (y en Ajustes del Sistema) e inténtalo de nuevo.",
      "service-not-allowed": "El navegador bloqueó el servicio de voz. Revisa los permisos del sitio o prueba con Chrome.",
      "audio-capture": "No se detectó ningún micrófono.",
      "network": "Problema de red al contactar el servicio de voz. Revisa tu conexión.",
      "no-speech": "No se detectó voz. Haz clic en Dictar y vuelve a hablar."
    };

    function setStatusError(message) {
      statusEl.classList.add("text-danger");
      setStatus(message);
    }

    recognition.onstart = function () {
      statusEl.classList.remove("text-danger");
      sawVoiceError = false;
      setRecordingUI(true);
      setStatus("Escuchando… describe tus gastos.");
      console.info("[ai_entry] SpeechRecognition started");
    };

    recognition.onresult = function (event) {
      var transcript = "";
      for (var i = event.resultIndex; i < event.results.length; i++) {
        transcript += event.results[i][0].transcript;
      }
      textarea.value = transcript.trim();
    };

    recognition.onerror = function (event) {
      sawVoiceError = true;
      console.warn("[ai_entry] SpeechRecognition error:", event.error);
      setStatusError(VOICE_ERRORS[event.error] ||
        "Falló el reconocimiento de voz (" + event.error + "). Puedes escribir en su lugar.");
    };

    recognition.onend = function () {
      setRecordingUI(false);
      if (textarea.value.trim()) {
        transcriptionWrap.classList.remove("d-none");
        transcriptionText.textContent = textarea.value.trim();
        parseExpenses();
      } else if (!sawVoiceError) {
        setStatusError("El dictado terminó sin capturar texto. Haz clic en Dictar e inténtalo de nuevo.");
      }
    };

    micButton.addEventListener("click", function () {
      if (recording) {
        recognition.stop();
      } else {
        try {
          recognition.start();
        } catch (error) {
          console.warn("[ai_entry] Could not start recognition:", error);
          setStatusError("No se pudo iniciar el reconocimiento de voz: " + error.message);
        }
      }
    });
  }

  // --------------------------------------------------------------------- init

  form.addEventListener("submit", function (event) {
    event.preventDefault();
    parseExpenses();
  });

  $("#aiAddRow").addEventListener("click", function () {
    rowsEl.appendChild(buildRow({ transaction_date: todayISO() }));
    updateTotal();
  });

  $("#aiSaveAll").addEventListener("click", saveExpenses);

  initVoice();
}

document.addEventListener("turbo:load", initializeAiEntry);
document.addEventListener("DOMContentLoaded", initializeAiEntry);
if (document.readyState !== "loading") initializeAiEntry();
