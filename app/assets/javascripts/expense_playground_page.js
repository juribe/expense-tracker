function initializePlayground() {
  var $ = function (sel) { return document.querySelector(sel); };

  var payloadEl = document.querySelector("[data-playground-payload]");
  var P = payloadEl ? JSON.parse(payloadEl.dataset.playgroundPayload) : {};
  var CATEGORIES = P.categories || [];
  var MONEY_SOURCES = P.money_sources || [];
  var T = P.texts || {};

  var HISTORY_KEY = "expense_playground_history_v1";
  var MAX_IMAGE_BYTES = 6 * 1024 * 1024;
  var MAX_AUDIO_BYTES = 15 * 1024 * 1024;
  var MAX_FILE_BYTES = 20 * 1024 * 1024;

  var state = { type: "text", imageData: null, imageName: null, audioData: null, audioName: null, fileData: null, fileName: null, lastResult: null, lastSteps: null, candidates: [], cards: [] };

  var form = $("#pgForm");
  if (!form || form.dataset.pgInitialized === "true") return;
  form.dataset.pgInitialized = "true";

  var textarea = $("#pgText");
  var dropzone = $("#pgDropzone");
  var imageFileInput = $("#pgFileInput");
  var audioDropzone = $("#pgAudioDropzone");
  var audioInput = $("#pgAudioInput");
  var processButton = $("#pgProcessButton");

  function csrfToken() {
    return (document.querySelector('meta[name="csrf-token"]') || {}).content || "";
  }

  function money(value) {
    var n = Number(value);
    if (!isFinite(n)) n = 0;
    return "$" + n.toLocaleString("en-US", { minimumFractionDigits: 0, maximumFractionDigits: 2 });
  }

  function formatConfidence(value) {
    if (value == null) return "—";
    return Math.round(Number(value) * 100) + "%";
  }

  function formatDate(iso) {
    if (!iso) return "—";
    var d = new Date(iso + "T00:00:00");
    return isNaN(d) ? iso : d.toLocaleDateString(undefined, { year: "numeric", month: "long", day: "numeric" });
  }

  function escapeHtml(text) {
    var div = document.createElement("div");
    div.textContent = text == null ? "" : String(text);
    return div.innerHTML;
  }

  // ----------------------------------------------------------------- tabs

  function setTab(type) {
    state.type = type;
    document.querySelectorAll("[data-pg-tab]").forEach(function (button) {
      button.classList.toggle("active", button.dataset.pgTab === type);
    });

    var showText = type === "text" || type === "text_image";
    var showImage = type === "image" || type === "text_image";
    var showAudio = type === "audio";
    var showFile = type === "file";
    $("#pgMainArea").classList.remove("d-none");
    $("#pgTextPanel").classList.toggle("d-none", !showText);
    $("#pgImagePanel").classList.toggle("d-none", !showImage);
    $("#pgAudioPanel").classList.toggle("d-none", !showAudio);
    $("#pgFilePanel").classList.toggle("d-none", !showFile);
    $("#pgTextImageHint").classList.toggle("d-none", type !== "text_image");
    if (type === "image") textarea.value = "";
    if (showAudio) textarea.value = "";
    if (showFile) textarea.value = "";
  }

  document.querySelectorAll("[data-pg-tab]").forEach(function (button) {
    button.addEventListener("click", function () { setTab(button.dataset.pgTab); });
  });

  // -------------------------------------------------------------- examples

  document.querySelectorAll(".pg-example").forEach(function (button) {
    button.addEventListener("click", function () {
      textarea.value = button.dataset.example;
      textarea.focus();
    });
  });

  // ----------------------------------------------------------------- image

  function showImage(dataUrl, name) {
    state.imageData = dataUrl;
    state.imageName = name;
    $("#pgImagePreview").src = dataUrl;
    $("#pgImageName").textContent = name || "";
    $("#pgImagePreviewWrap").classList.remove("d-none");
    $("#pgDropzoneLabel").textContent = T.changeImage || "";
    dropzone.classList.add("pg-dropzone-filled");
  }

  function clearImage() {
    state.imageData = null;
    state.imageName = null;
    imageFileInput.value = "";
    $("#pgImagePreviewWrap").classList.add("d-none");
    $("#pgDropzoneLabel").textContent = T.changeImage_label || "";
    dropzone.classList.remove("pg-dropzone-filled");
  }

  function acceptFile(file) {
    if (!file) return;
    if (!/^image\/(jpeg|png|webp|gif)$/.test(file.type)) {
      showError(T.imageUnsupported || "Unsupported image format. Use JPEG, PNG, WebP or GIF.");
      return;
    }
    if (file.size > MAX_IMAGE_BYTES) {
      showError((T.imageTooLarge || "Image is too large (max %{max} MB).").replace("%{max}", MAX_IMAGE_BYTES / (1024 * 1024)));
      return;
    }
    var reader = new FileReader();
    reader.onload = function () { showImage(reader.result, file.name); };
    reader.readAsDataURL(file);
  }

  dropzone.addEventListener("click", function () { imageFileInput.click(); });
  dropzone.addEventListener("keydown", function (event) {
    if (event.key === "Enter" || event.key === " ") { event.preventDefault(); imageFileInput.click(); }
  });
  imageFileInput.addEventListener("change", function () { acceptFile(imageFileInput.files[0]); });
  ["dragover", "dragenter"].forEach(function (event) {
    dropzone.addEventListener(event, function (e) { e.preventDefault(); dropzone.classList.add("pg-dropzone-over"); });
  });
  ["dragleave", "drop"].forEach(function (event) {
    dropzone.addEventListener(event, function (e) { e.preventDefault(); dropzone.classList.remove("pg-dropzone-over"); });
  });
  dropzone.addEventListener("drop", function (e) {
    if (e.dataTransfer && e.dataTransfer.files.length) acceptFile(e.dataTransfer.files[0]);
  });
  $("#pgRemoveImage").addEventListener("click", clearImage);

  // ----------------------------------------------------------------- audio

  function audioExtension(name) {
    var match = (name || "").toLowerCase().match(/\.([a-z0-9]+)$/);
    return match ? match[1] : "";
  }

  function showAudio(dataUrl, name, file) {
    state.audioData = dataUrl;
    state.audioName = name;
    $("#pgAudioPreview").src = dataUrl;
    $("#pgAudioName").textContent = name || "";
    $("#pgAudioPreviewWrap").classList.remove("d-none");
    $("#pgAudioDropzoneLabel").textContent = T.changeAudio || "";
    audioDropzone.classList.add("pg-dropzone-filled");
    var player = $("#pgAudioPreview");
    player.onloadedmetadata = function () {
      var seconds = player.duration;
      $("#pgAudioMeta").textContent = isFinite(seconds) && seconds > 0
        ? (T.audioSeconds || "%{seconds} s").replace("%{seconds}", seconds.toFixed(1))
        : "";
    };
  }

  function clearAudio() {
    state.audioData = null;
    state.audioName = null;
    audioInput.value = "";
    $("#pgAudioPreview").removeAttribute("src");
    $("#pgAudioPreviewWrap").classList.add("d-none");
    $("#pgAudioMeta").textContent = "";
    $("#pgAudioDropzoneLabel").textContent = T.audio_upload_label || "";
    audioDropzone.classList.remove("pg-dropzone-filled");
  }

  function acceptAudio(file) {
    if (!file) return;
    var type = file.type || "";
    if (!/^audio\//.test(type) && [ "ogg", "opus", "m4a", "mp3", "wav", "webm" ].indexOf(audioExtension(file.name)) === -1) {
      showError(T.audioUnsupported || "Unsupported audio format. Use OGG, OPUS, M4A, MP3, WAV or WEBM.");
      return;
    }
    if (file.size > MAX_AUDIO_BYTES) {
      showError((T.audioTooLarge || "Audio is too large (max %{max} MB).").replace("%{max}", MAX_AUDIO_BYTES / (1024 * 1024)));
      return;
    }
    var reader = new FileReader();
    reader.onload = function () { showAudio(reader.result, file.name, file); };
    reader.readAsDataURL(file);
  }

  audioDropzone.addEventListener("click", function () { audioInput.click(); });
  audioDropzone.addEventListener("keydown", function (event) {
    if (event.key === "Enter" || event.key === " ") { event.preventDefault(); audioInput.click(); }
  });
  audioInput.addEventListener("change", function () { acceptAudio(audioInput.files[0]); });
  ["dragover", "dragenter"].forEach(function (event) {
    audioDropzone.addEventListener(event, function (e) { e.preventDefault(); audioDropzone.classList.add("pg-dropzone-over"); });
  });
  ["dragleave", "drop"].forEach(function (event) {
    audioDropzone.addEventListener(event, function (e) { e.preventDefault(); audioDropzone.classList.remove("pg-dropzone-over"); });
  });
  audioDropzone.addEventListener("drop", function (e) {
    if (e.dataTransfer && e.dataTransfer.files.length) acceptAudio(e.dataTransfer.files[0]);
  });
  $("#pgRemoveAudio").addEventListener("click", clearAudio);

  // ------------------------------------------------------------------- file

  function fileExtension(name) {
    var match = (name || "").toLowerCase().match(/\.([a-z0-9]+)$/);
    return match ? match[1] : "";
  }

  function showFileData(name) {
    $("#pgFileName").textContent = name || "";
    $("#pgFilePreviewWrap").classList.remove("d-none");
    $("#pgFileDropzoneLabel").textContent = T.changeFile || "";
    var ext = fileExtension(name);
    $("#pgPdfPasswordWrap").classList.toggle("d-none", ext !== "pdf");
  }

  function clearFile() {
    state.fileData = null;
    state.fileName = null;
    fileInput.value = "";
    $("#pgFileName").textContent = "";
    $("#pgFilePreviewWrap").classList.add("d-none");
    $("#pgPdfPasswordWrap").classList.add("d-none");
    $("#pgPdfPassword").value = "";
    $("#pgFileDropzoneLabel").textContent = T.file_upload_label || "";
  }

  function acceptStatementFile(file) {
    if (!file) return;
    var ext = fileExtension(file.name);
    if (ext !== "pdf" && ext !== "csv" && ext !== "xlsx" && ext !== "xls") {
      showError(T.fileUnsupported || "Unsupported file format. Use PDF, CSV, or Excel.");
      return;
    }
    if (file.size > MAX_FILE_BYTES) {
      showError((T.fileTooLarge || "File is too large (max 20 MB)."));
      return;
    }
    var reader = new FileReader();
    reader.onload = function () {
      state.fileData = reader.result;
      state.fileName = file.name;
      showFileData(file.name);
    };
    reader.readAsDataURL(file);
  }

  var fileDropzone = $("#pgFileDropzone");
  var fileInput = $("#pgStatementFileInput");

  fileDropzone.addEventListener("click", function () { fileInput.click(); });
  fileDropzone.addEventListener("keydown", function (event) {
    if (event.key === "Enter" || event.key === " ") { event.preventDefault(); fileInput.click(); }
  });
  fileInput.addEventListener("change", function () { acceptStatementFile(fileInput.files[0]); });
  ["dragover", "dragenter"].forEach(function (event) {
    fileDropzone.addEventListener(event, function (e) { e.preventDefault(); fileDropzone.classList.add("pg-dropzone-over"); });
  });
  ["dragleave", "drop"].forEach(function (event) {
    fileDropzone.addEventListener(event, function (e) { e.preventDefault(); fileDropzone.classList.remove("pg-dropzone-over"); });
  });
  fileDropzone.addEventListener("drop", function (e) {
    if (e.dataTransfer && e.dataTransfer.files.length) acceptStatementFile(e.dataTransfer.files[0]);
  });
  $("#pgRemoveFile").addEventListener("click", clearFile);

  // -------------------------------------------------------------- processing

  function setLoading(button, spinner, icon, label, busy, busyText, idleText) {
    button.disabled = busy;
    spinner.classList.toggle("d-none", !busy);
    icon.classList.toggle("d-none", busy);
    label.textContent = busy ? busyText : idleText;
  }

  function showError(message) {
    var error = $("#pgResultErrors");
    error.textContent = message;
    error.classList.remove("d-none");
    $("#pgResult").classList.remove("d-none");
    $("#pgResultEmpty").classList.add("d-none");
  }

  function currentTypeLabel() {
    return { text: T.tabText, image: T.tabImage, text_image: T.tabTextImage, audio: T.tabAudio, file: T.tabFile }[state.type] || state.type;
  }

  function processFileInput() {
    if (!state.fileData) { fileDropzone.focus(); return; }

    setLoading(processButton, $("#pgProcessSpinner"), $(".pg-process-icon"), $("#pgProcessLabel"),
      true, T.processing, T.process);

    fetch(form.dataset.processFileUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json", "Accept": "application/json", "X-CSRF-Token": csrfToken() },
      body: JSON.stringify({
        file_data: state.fileData,
        filename: state.fileName || "upload",
        password: $("#pgPdfPassword").value || null,
        input_label: state.fileName || "file"
      })
    }).then(function (response) {
      return response.json().then(function (data) { return { ok: response.ok, data: data }; });
    }).then(function (result) {
      setLoading(processButton, $("#pgProcessSpinner"), $(".pg-process-icon"), $("#pgProcessLabel"),
        false, T.processing, T.process);
      handleFileResult(result.ok, result.data);
    }).catch(function () {
      setLoading(processButton, $("#pgProcessSpinner"), $(".pg-process-icon"), $("#pgProcessLabel"),
        false, T.processing, T.process);
      showError(T.fileProcessingFailed || "File processing failed. Please try again.");
    });
  }

  function renderFileCandidates(candidates) {
    var rows = $("#pgFileRows");
    rows.textContent = "";

    candidates.forEach(function (candidate, index) {
      var row = document.createElement("tr");
      row.setAttribute("data-testid", "file-candidate-row");
      var date = candidate.date || "";
      var amount = money(candidate.amount);
      var confidence = formatConfidence(candidate.confidence);
      var status = "";
      if (candidate.duplicate) {
        status = '<span class="badge bg-warning text-dark" data-testid="file-candidate-duplicate" title="' +
          escapeHtml(T.duplicateHint || "Possible duplicate: same date, amount and money source.") + '">' +
          '<i class="ti ti-alert-triangle me-1" aria-hidden="true"></i>' +
          escapeHtml(T.duplicateLabel || "Possible duplicate") + "</span>";
      } else {
        status = '<span class="badge bg-success" data-testid="file-candidate-ready">' +
          escapeHtml(T.readyLabel || "Ready") + "</span>";
      }
      row.innerHTML =
        '<td class="small">' + escapeHtml(date ? new Date(date + "T00:00:00").toLocaleDateString() : "—") + "</td>" +
        '<td class="small">' + escapeHtml(candidate.description || "—") +
        (candidate.classification_source ? '<div class="small text-muted">' + escapeHtml(T.classificationSourceLabel || "Classification") +
          ": " + escapeHtml(candidate.classification_source) + "</div>" : "") +
        (candidate.money_source_source ? '<div class="small text-muted">' + escapeHtml(T.moneySourceSourceLabel || "Money source") +
          ": " + escapeHtml(candidate.money_source_source) + "</div>" : "") +
        "</td>" +
        '<td class="small text-end fw-semibold">' + escapeHtml(amount) + " " + escapeHtml(candidate.currency || "COP") + "</td>" +
        '<td class="small">' + escapeHtml(candidate.category_name || T.noCategory) + "</td>" +
        '<td class="small">' + escapeHtml(candidate.money_source_name || "—") + "</td>" +
        '<td class="small">' + escapeHtml(confidence) + "</td>" +
        '<td class="small">' + status + "</td>";
      rows.appendChild(row);
    });
  }

  function handleFileResult(ok, data) {
    $("#pgFileResult").classList.remove("d-none");
    $("#pgResultEmpty").classList.add("d-none");

    var errors = (data.errors || []);
    var errorBox = $("#pgFileErrors");
    if (errors.length) {
      errorBox.textContent = (T.fileErrorsTitle || "Errors") + ": " + errors.join(" ");
      errorBox.classList.remove("d-none");
    } else {
      errorBox.classList.add("d-none");
    }

    var sources = data.sources || [];
    var sourceBox = $("#pgFileSources");
    if (sources.length) {
      var names = sources.map(function (s) { return s.display_name || s.name || "source"; });
      sourceBox.innerHTML = '<div class="alert alert-info py-2 small mb-0" data-testid="playground-file-sources-list">' +
        '<i class="ti ti-wallet me-1" aria-hidden="true"></i><strong>' + escapeHtml(T.tabFile || "File") + ":</strong> " +
        escapeHtml(names.join(", ")) + "</div>";
      sourceBox.classList.remove("d-none");
    } else {
      sourceBox.classList.add("d-none");
    }

    var candidates = data.candidates || [];
    state.lastFileCandidates = candidates;
    $("#pgFileCount").textContent = candidates.length + (candidates.length === 1 ? " transaction" : " transactions");
    renderFileCandidates(candidates);

    var hasUsable = candidates.length > 0;
    $("#pgFileCreateButton").classList.toggle("d-none", !hasUsable);
    if (!hasUsable && errors.length === 0) showError(T.fileNoTransactions || "No transactions could be extracted from this file.");
    loadAiSummary();
  }

  function fileCandidatesFromPreview() {
    return state.lastFileCandidates || [];
  }

  function createAllExpenses() {
    var candidates = fileCandidatesFromPreview();
    if (!candidates.length) return;

    setLoading($("#pgFileCreateButton"), $("#pgFileCreateSpinner"), $(".pg-file-create-icon"), $("#pgFileCreateLabel"),
      true, T.fileCreating, T.fileCreateAll);

    fetch(form.dataset.batchCreateUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json", "Accept": "application/json", "X-CSRF-Token": csrfToken() },
      body: JSON.stringify({ candidates: candidates })
    }).then(function (response) {
      return response.json().then(function (data) { return { ok: response.ok, data: data }; });
    }).then(function (result) {
      setLoading($("#pgFileCreateButton"), $("#pgFileCreateSpinner"), $(".pg-file-create-icon"), $("#pgFileCreateLabel"),
        false, T.fileCreating, T.fileCreateAll);
      var success = $("#pgFileCreateSuccess");
      if (result.ok) {
        $("#pgFileCreateSuccessText").textContent = (T.fileCreated || "Expenses created successfully.")
          .replace("%{count}", (result.data.created || []).length);
        success.classList.remove("d-none");
        $("#pgFileCreateButton").classList.add("d-none");
      } else {
        var errs = (result.data.errors || []);
        var msg = errs.length ? errs.map(function (e) {
          return (e.index != null ? (T.rowLabel || "Row %{index}: ").replace("%{index}", e.index) : "") + (Array.isArray(e.errors) ? e.errors.join(" ") : "");
        }).join("; ") : (T.someExpensesFailed || "Some expenses could not be created.");
        showError(msg);
      }
    }).catch(function () {
      setLoading($("#pgFileCreateButton"), $("#pgFileCreateSpinner"), $(".pg-file-create-icon"), $("#pgFileCreateLabel"),
        false, T.fileCreating, T.fileCreateAll);
      showError(T.createFailed || "The expenses could not be created. Please try again.");
    });
  }

  $("#pgFileCreateButton").addEventListener("click", createAllExpenses);

  function processInput() {
    var type = state.type;
    if (type === "file") { processFileInput(); return; }
    var text = type === "image" || type === "audio" ? "" : textarea.value.trim();
    if ((type === "text" || type === "text_image") && !text) { textarea.focus(); return; }
    if (type !== "text" && !state.imageData && (type !== "audio" || !state.audioData)) { dropzone.focus(); return; }
    if (type === "audio" && !state.audioData) { audioDropzone.focus(); return; }

    setLoading(processButton, $("#pgProcessSpinner"), $(".pg-process-icon"), $("#pgProcessLabel"),
      true, T.processing, T.process);
    state.cards.forEach(function (entry) {
      entry.root.querySelector(".pg-card-success").classList.add("d-none");
    });

    fetch(form.dataset.processUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json", "Accept": "application/json", "X-CSRF-Token": csrfToken() },
      body: JSON.stringify({
        type: type,
        text: text,
        image_data: type === "text" ? null : state.imageData,
        audio_data: type === "audio" ? state.audioData : null,
        filename: type === "audio" ? (state.audioName || "audio") : null,
        input_label: type === "image" ? (state.imageName || "image")
          : type === "audio" ? (state.audioName || "audio") : text,
        expected: collectExpected()
      })
    }).then(function (response) {
      return response.json().then(function (data) { return { ok: response.ok, data: data }; });
    }).then(function (result) {
      setLoading(processButton, $("#pgProcessSpinner"), $(".pg-process-icon"), $("#pgProcessLabel"),
        false, T.processing, T.process);
      handleProcessResult(result.ok, result.data);
    }).catch(function () {
      setLoading(processButton, $("#pgProcessSpinner"), $(".pg-process-icon"), $("#pgProcessLabel"),
        false, T.processing, T.process);
      showError("Fallo en el procesamiento. inténtalo de nuevo.");
    });
  }

  function handleProcessResult(ok, data) {
    state.lastResult = data;
    state.lastSteps = data.steps;
    state.candidates = data.candidates && data.candidates.length
      ? data.candidates
      : (data.candidate ? [data.candidate] : []);
    renderSttSummary(data.steps);
    renderSteps(data);
    loadAiSummary();
    $("#pgDebug").classList.remove("d-none");

    var errors = (data.errors || []).join(" ");
    if (!state.candidates.length) {
      showError(errors || (T.extractFailed || "Could not extract an expense from this input."));
      return;
    }
    if (errors) showError(errors); else $("#pgResultErrors").classList.add("d-none");
    if (data.warnings && data.warnings.length) {
      var warnings = $("#pgResultWarnings");
      warnings.innerHTML = "<strong>" + escapeHtml(T.warningsTitle) + ":</strong> " + escapeHtml(data.warnings.join(" "));
      warnings.classList.remove("d-none");
    } else {
      $("#pgResultWarnings").classList.add("d-none");
    }

    // Evaluations arrive one per candidate, in the same order as `candidates`.
    var evaluations = data.evaluations && data.evaluations.length
      ? data.evaluations
      : (data.evaluation ? [data.evaluation] : null);
    renderCards(state.candidates, evaluations);
    $("#pgResultEmpty").classList.add("d-none");
    $("#pgResult").classList.remove("d-none");

    addHistoryEntry({
      id: data.run_id,
      ts: Date.now(),
      type: state.type,
      label: state.type === "image" ? (state.imageName || "image")
        : state.type === "audio" ? (state.audioName || "audio") : textarea.value.trim(),
      candidate: state.candidates[0],
      candidates: state.candidates,
      steps: data.steps,
      ok: ok,
      confidence: state.candidates[0].confidence
    });
  }

  // ------------------------------------------------------------- evaluation

  function collectExpected() {
    var expected = {};
    var amount = $("#pgExpectedAmount").value.trim();
    var category = $("#pgExpectedCategory").value.trim();
    var description = $("#pgExpectedDescription").value.trim();
    var date = $("#pgExpectedDate").value;
    var source = $("#pgExpectedSource").value.trim();
    if (amount) expected.amount = amount;
    if (category) expected.category = category;
    if (description) expected.description = description;
    if (date) expected.date = date;
    if (source) expected.source = source;
    return Object.keys(expected).length ? expected : null;
  }

  // ----------------------------------------------------- transcript / stt meta

  function renderSttSummary(steps) {
    var stt = steps && steps.stt;
    var hasTranscript = stt && stt.applicable && stt.text;
    var wrap = $("#pgTranscript");
    wrap.classList.toggle("d-none", !hasTranscript);
    if (hasTranscript) $("#pgTranscriptText").textContent = stt.text;

    var meta = $("#pgSttMeta");
    var hasMeta = stt && stt.applicable && (stt.provider || stt.error);
    meta.classList.toggle("d-none", !hasMeta);
    if (!hasMeta) return;
    $("#pgSttProvider").textContent = stt.provider ? stt.provider.charAt(0).toUpperCase() + stt.provider.slice(1) : "—";
    $("#pgSttModel").textContent = stt.model || "—";
    $("#pgSttLanguage").textContent = stt.language || "—";
    $("#pgSttDuration").textContent = stt.duration != null
      ? (T.audioSeconds || "%{seconds} s").replace("%{seconds}", Number(stt.duration).toFixed(1))
      : "—";
  }

  // ----------------------------------------------------------------- result

  function categoryOption(value, label, selected) {
    var opt = document.createElement("option");
    opt.value = value;
    opt.textContent = label;
    opt.selected = !!selected;
    return opt;
  }

  function fillCategorySelect(select, categoryId, categoryName) {
    select.textContent = "";
    var matched = null;
    if (categoryId) {
      matched = CATEGORIES.filter(function (c) { return Number(c.id) === Number(categoryId); })[0];
    }
    if (!matched && !categoryName) {
      // Unassigned candidate: require an explicit choice before confirming.
      select.appendChild(categoryOption("", T.selectCategory, true));
    }
    CATEGORIES.forEach(function (category) {
      select.appendChild(categoryOption(category.id, category.name, !!(matched && Number(matched.id) === Number(category.id))));
    });
    if (!matched && categoryName) {
      select.appendChild(categoryOption("new:" + categoryName, categoryName, true));
    }
  }

  function fillSourceSelect(select, sourceId, sourceName) {
    select.textContent = "";
    var matched = null;
    if (sourceId) {
      matched = MONEY_SOURCES.filter(function (source) { return Number(source.id) === Number(sourceId); })[0];
    }
    select.appendChild(categoryOption("", T.noSource, !matched && !sourceName));
    MONEY_SOURCES.forEach(function (source) {
      select.appendChild(categoryOption(source.id, source.display_name, !!(matched && Number(matched.id) === Number(source.id))));
    });
    if (!matched && sourceName) {
      var unknown = categoryOption("", sourceName, true);
      unknown.disabled = true;
      select.appendChild(unknown);
    }
  }

  function sourceLabel(candidate) {
    if (candidate.money_source_name) return candidate.money_source_name;
    var matched = candidate.money_source_id
      ? MONEY_SOURCES.filter(function (source) { return Number(source.id) === Number(candidate.money_source_id); })[0]
      : null;
    return matched ? matched.name : T.noSource;
  }

  // One editable accordion item per detected candidate. Items are built from
  // a shared skeleton and scoped queries (`.pg-*` classes) instead of fixed
  // ids so the same UI renders any number of expenses.
  function cardSkeleton(index, open) {
    var card = document.createElement("div");
    card.className = "accordion-item pg-expense-card";
    card.setAttribute("data-testid", "expense-card");
    var collapseId = "pgResultCardCollapse" + index;
    card.innerHTML =
      '<h2 class="accordion-header" id="pgResultCardHeading' + index + '">' +
      '<button class="accordion-button' + (open ? "" : " collapsed") + '" type="button"' +
      ' data-bs-toggle="collapse" data-bs-target="#' + collapseId + '"' +
      ' aria-expanded="' + (open ? "true" : "false") + '" aria-controls="' + collapseId + '"' +
      ' data-testid="playground-expense-card-toggle">' +
      '<span class="pg-card-title"></span>' +
      '<span class="badge bg-secondary pg-card-confidence ms-2" data-testid="card-confidence"></span>' +
      "</button></h2>" +
      '<div id="' + collapseId + '" class="accordion-collapse collapse' + (open ? " show" : "") + '"' +
      ' aria-labelledby="pgResultCardHeading' + index + '">' +
      '<div class="accordion-body">' +
      '<dl class="row mb-0" data-testid="detected-expense">' +
      '<dt class="col-5 small text-muted">' + escapeHtml(T.amountLabel) + '</dt>' +
      '<dd class="col-7 fw-semibold pg-sum-amount" data-testid="detected-amount"></dd>' +
      '<dt class="col-5 small text-muted">' + escapeHtml(T.categoryLabel) + '</dt>' +
      '<dd class="col-7 pg-sum-category" data-testid="detected-category"></dd>' +
      '<dt class="col-5 small text-muted">' + escapeHtml(T.descriptionLabel) + '</dt>' +
      '<dd class="col-7 pg-sum-description" data-testid="detected-description"></dd>' +
      '<dt class="col-5 small text-muted">' + escapeHtml(T.dateLabel) + '</dt>' +
      '<dd class="col-7 pg-sum-date" data-testid="detected-date"></dd>' +
      '<dt class="col-5 small text-muted">' + escapeHtml(T.sourceLabel) + '</dt>' +
      '<dd class="col-7 pg-sum-source" data-testid="detected-source"></dd>' +
      '<dt class="col-5 small text-muted">' + escapeHtml(T.merchantLabel) + '</dt>' +
      '<dd class="col-7 pg-sum-merchant" data-testid="detected-merchant"></dd>' +
      '<dt class="col-5 small text-muted">Status</dt>' +
      '<dd class="col-7 pg-sum-status" data-testid="detected-status"></dd>' +
      '<dt class="col-5 small text-muted">Category Suggestion</dt>' +
      '<dd class="col-7 pg-sum-category-suggestion" data-testid="detected-category-suggestion"></dd>' +
      "</dl>" +
      '<div class="pg-card-evaluation mt-3 d-none" data-testid="playground-evaluation">' +
      '<hr class="mt-2 mb-2">' +
      '<div class="d-flex justify-content-between align-items-center mb-1">' +
      '<h3 class="h6 mb-0"><i class="ti ti-target me-1" aria-hidden="true"></i>' + escapeHtml(T.evaluationTitle) + '</h3>' +
      '<span class="badge bg-success pg-evaluation-score" data-testid="evaluation-score"></span>' +
      "</div>" +
      '<table class="table table-sm mb-0"><thead><tr>' +
      '<th class="small text-muted">' + escapeHtml(T.evaluationField) + "</th>" +
      '<th class="small text-muted">' + escapeHtml(T.evaluationExpected) + "</th>" +
      '<th class="small text-muted">' + escapeHtml(T.evaluationDetected) + "</th>" +
      "<th></th>" +
      "</tr></thead><tbody class=\"pg-evaluation-body\"></tbody></table>" +
      "</div>" +
      "<hr>" +
      '<h3 class="h6 mb-2">' + escapeHtml(T.editTitle) + "</h3>" +
      '<p class="small text-muted">' + escapeHtml(T.editHint) + "</p>" +
      '<div class="row g-2" data-testid="playground-edit-form">' +
      '<div class="col-6"><label class="form-label small mb-1">' + escapeHtml(T.amountLabel) + "</label>" +
      '<input type="number" min="0" step="any" class="form-control form-control-sm pg-edit-amount" data-testid="edit-amount"></div>' +
      '<div class="col-6"><label class="form-label small mb-1">' + escapeHtml(T.currencyLabel) + "</label>" +
      '<input type="text" class="form-control form-control-sm pg-edit-currency" data-testid="edit-currency"></div>' +
      '<div class="col-12"><label class="form-label small mb-1">' + escapeHtml(T.categoryLabel) + "</label>" +
      '<select class="form-select form-select-sm pg-edit-category" data-testid="edit-category"></select></div>' +
      '<div class="col-12"><label class="form-label small mb-1">' + escapeHtml(T.descriptionLabel) + "</label>" +
      '<input type="text" class="form-control form-control-sm pg-edit-description" data-testid="edit-description"></div>' +
      '<div class="col-12"><label class="form-label small mb-1">' + escapeHtml(T.sourceLabel) + "</label>" +
      '<select class="form-select form-select-sm pg-edit-source" data-testid="edit-source"></select></div>' +
      '<div class="col-6"><label class="form-label small mb-1">' + escapeHtml(T.merchantLabel) + "</label>" +
      '<input type="text" class="form-control form-control-sm pg-edit-merchant" data-testid="edit-merchant"></div>' +
      '<div class="col-6"><label class="form-label small mb-1">' + escapeHtml(T.dateLabel) + "</label>" +
      '<input type="date" class="form-control form-control-sm pg-edit-date" data-testid="edit-date"></div>' +
      "</div>" +
      '<div class="alert alert-success mt-3 d-none pg-card-success" role="alert" data-testid="playground-success">' +
      '<i class="ti ti-circle-check me-1" aria-hidden="true"></i>' +
      '<span class="pg-card-success-text"></span>' +
      '<a href="/expenses" class="alert-link ms-1">' + escapeHtml(T.viewExpenses) + "</a>" +
      "</div>" +
      '<button type="button" class="btn btn-success w-100 mt-3 pg-create-button" data-testid="playground-create-button">' +
      '<span class="spinner-border spinner-border-sm d-none me-1 pg-create-spinner" aria-hidden="true"></span>' +
      '<i class="ti ti-circle-plus me-1 pg-create-icon" aria-hidden="true"></i>' +
      '<span class="pg-create-label">' + escapeHtml(T.createExpense) + "</span>" +
      "</button>" +
      "</div></div>";
    return card;
  }

  function renderCardEvaluation(card, evaluation) {
    var wrap = card.querySelector(".pg-card-evaluation");
    if (!evaluation || !evaluation.checks || !evaluation.checks.length) {
      wrap.classList.add("d-none");
      return;
    }

    var score = wrap.querySelector(".pg-evaluation-score");
    var evaluationOk = typeof evaluation.ok === "boolean" ? evaluation.ok : evaluation["ok?"];
    score.textContent = T.evaluationCorrect
      .replace("%{passed}", evaluation.passed)
      .replace("%{total}", evaluation.total);
    score.classList.toggle("bg-success", !!evaluationOk);
    score.classList.toggle("bg-danger", !evaluationOk);

    var body = wrap.querySelector(".pg-evaluation-body");
    body.textContent = "";
    evaluation.checks.forEach(function (check) {
      var row = document.createElement("tr");
      row.setAttribute("data-testid", "evaluation-check");
      row.innerHTML =
        '<td class="small fw-semibold">' + escapeHtml(check.field) + "</td>" +
        '<td class="small">' + escapeHtml(check.expected) + "</td>" +
        '<td class="small">' + escapeHtml(check.actual || "—") + "</td>" +
        '<td class="small ' + (check.passed ? "text-success" : "text-danger") + '">' +
        (check.passed ? "✓" : "✗") + "</td>";
      body.appendChild(row);
    });
    wrap.classList.remove("d-none");
  }

  function fillCard(card, candidate, index) {
    var description = candidate.description || candidate.merchant;
    card.querySelector(".pg-card-title").textContent =
      (T.expenseN || "Expense %{n}").replace("%{n}", index + 1) + ": " + (description || "—");
    card.querySelector(".pg-sum-amount").textContent = money(candidate.amount) + " " + (candidate.currency || "COP");
    card.querySelector(".pg-sum-category").textContent = candidate.category_name || T.noCategory;
    card.querySelector(".pg-sum-description").textContent = candidate.description || "—";
    card.querySelector(".pg-sum-date").textContent = formatDate(candidate.date);
    card.querySelector(".pg-sum-source").textContent = sourceLabel(candidate);
    card.querySelector(".pg-sum-merchant").textContent = candidate.merchant || T.noMerchant;
    card.querySelector(".pg-sum-status").textContent = candidate.status || "—";
    card.querySelector(".pg-sum-category-suggestion").textContent = candidate.category_suggestion || "—";
    card.querySelector(".pg-card-confidence").textContent = formatConfidence(candidate.confidence);

    card.querySelector(".pg-edit-amount").value = candidate.amount != null ? candidate.amount : "";
    card.querySelector(".pg-edit-currency").value = candidate.currency || "COP";
    fillCategorySelect(card.querySelector(".pg-edit-category"), candidate.category_id, candidate.category_name);
    fillSourceSelect(card.querySelector(".pg-edit-source"), candidate.money_source_id, candidate.money_source_name);
    card.querySelector(".pg-edit-description").value = candidate.description || "";
    card.querySelector(".pg-edit-merchant").value = candidate.merchant || "";
    card.querySelector(".pg-edit-date").value = candidate.date || new Date().toISOString().slice(0, 10);
  }

  function renderCards(candidates, evaluations) {
    var container = $("#pgCards");
    container.textContent = "";
    container.className = "accordion";
    state.cards = [];

    (candidates || []).forEach(function (candidate, index) {
      var card = cardSkeleton(index, index === 0);
      fillCard(card, candidate, index);
      if (evaluations && evaluations[index]) renderCardEvaluation(card, evaluations[index]);
      card.querySelector(".pg-create-button").addEventListener("click", function () { createCardExpense(index); });
      container.appendChild(card);
      state.cards.push({ root: card, candidate: candidate, created: false });
    });

    var count = state.cards.length;
    var badge = $("#pgResultCount");
    badge.textContent = String(count);
    badge.classList.toggle("d-none", count <= 1);
    wireAccordionToggle(container, $("#pgResultToggle"), $("#pgResultToggleIcon"));
    updateCreateAllButton();
  }

  function collectCardCandidate(index) {
    var entry = state.cards[index] || {};
    var card = entry.root;
    var categorySelect = card.querySelector(".pg-edit-category");
    var sourceSelect = card.querySelector(".pg-edit-source");
    var isNewCategory = categorySelect.value.indexOf("new:") === 0;
    var lastCandidate = entry.candidate || {};
    var selectedSource = sourceSelect.selectedOptions[0] || {};
    return {
      amount: card.querySelector(".pg-edit-amount").value,
      currency: card.querySelector(".pg-edit-currency").value,
      category_id: isNewCategory ? "" : categorySelect.value,
      category_name: isNewCategory ? categorySelect.value.slice(4) : (categorySelect.value ? (categorySelect.selectedOptions[0] || {}).textContent || "" : ""),
      description: card.querySelector(".pg-edit-description").value,
      merchant: card.querySelector(".pg-edit-merchant").value,
      date: card.querySelector(".pg-edit-date").value,
      source: "playground",
      confidence: lastCandidate.confidence || null,
      money_source_id: sourceSelect.value || null,
      money_source_name: sourceSelect.value ? (selectedSource.textContent || null) : (lastCandidate.money_source_name || null)
    };
  }

  function pendingCardIndexes() {
    return state.cards
      .map(function (entry, index) { return entry.created ? null : index; })
      .filter(function (index) { return index != null; });
  }

  function markCardCreated(index, message) {
    var entry = state.cards[index];
    entry.created = true;
    var card = entry.root;
    card.querySelector(".pg-card-success-text").textContent = message;
    card.querySelector(".pg-card-success").classList.remove("d-none");
    card.querySelector(".pg-create-button").classList.add("d-none");
    card.querySelector(".pg-create-button").disabled = true;
  }

  function updateCreateAllButton() {
    var button = $("#pgCreateAllButton");
    var pending = pendingCardIndexes();
    button.classList.toggle("d-none", state.cards.length <= 1 || pending.length === 0);
  }

  function currentRunId() {
    return state.lastResult ? (state.lastResult.run_id || state.lastResult.id) : null;
  }

  function createCardExpense(index) {
    var entry = state.cards[index];
    var card = entry.root;
    var candidate = collectCardCandidate(index);
    if (!candidate.amount || Number(candidate.amount) <= 0) {
      card.querySelector(".pg-edit-amount").focus();
      return;
    }
    if (!candidate.category_id && !candidate.category_name) {
      card.querySelector(".pg-edit-category").focus();
      return;
    }

    setLoading(card.querySelector(".pg-create-button"), card.querySelector(".pg-create-spinner"),
      card.querySelector(".pg-create-icon"), card.querySelector(".pg-create-label"),
      true, T.creating, T.createExpense);

    fetch(form.dataset.createUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json", "Accept": "application/json", "X-CSRF-Token": csrfToken() },
      body: JSON.stringify({
        candidate: candidate,
        run_id: currentRunId()
      })
    }).then(function (response) {
      return response.json().then(function (data) { return { ok: response.ok, data: data }; });
    }).then(function (result) {
      setLoading(card.querySelector(".pg-create-button"), card.querySelector(".pg-create-spinner"),
        card.querySelector(".pg-create-icon"), card.querySelector(".pg-create-label"),
        false, T.creating, T.createExpense);
      if (result.ok) {
        markCardCreated(index, result.data.message || T.expenseCreated);
      } else {
        showError((result.data.errors || []).join(" ") || (T.createOneFailed || "The expense could not be created."));
      }
    }).catch(function () {
      setLoading(card.querySelector(".pg-create-button"), card.querySelector(".pg-create-spinner"),
        card.querySelector(".pg-create-icon"), card.querySelector(".pg-create-label"),
        false, T.creating, T.createExpense);
      showError(T.createOneFailed || "The expense could not be created. Please try again.");
    });
  }

  function createAllDetected() {
    var indexes = pendingCardIndexes();
    if (!indexes.length) return;

    var candidates = indexes.map(collectCardCandidate);
    setLoading($("#pgCreateAllButton"), $("#pgCreateAllSpinner"),
      $("#pgCreateAllButton .pg-create-all-icon"), $("#pgCreateAllLabel"),
      true, T.fileCreating, T.createAll);

    fetch(form.dataset.batchCreateUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json", "Accept": "application/json", "X-CSRF-Token": csrfToken() },
      body: JSON.stringify({ candidates: candidates })
    }).then(function (response) {
      return response.json().then(function (data) { return { ok: response.ok, data: data }; });
    }).then(function (result) {
      setLoading($("#pgCreateAllButton"), $("#pgCreateAllSpinner"),
        $("#pgCreateAllButton .pg-create-all-icon"), $("#pgCreateAllLabel"),
        false, T.fileCreating, T.createAll);
      if (result.ok) {
        var count = (result.data.created || []).length;
        var message = (T.fileCreated || "Expenses created successfully.").replace("%{count}", count);
        indexes.forEach(function (index) { markCardCreated(index, message); });
      } else {
        var errs = (result.data.errors || []);
        var msg = errs.length ? errs.map(function (e) {
          return (e.index != null ? (T.rowLabel || "Row %{index}: ").replace("%{index}", e.index) : "") + (Array.isArray(e.errors) ? e.errors.join(" ") : "");
        }).join("; ") : (T.someExpensesFailed || "Some expenses could not be created.");
        showError(msg);
      }
      updateCreateAllButton();
    }).catch(function () {
      setLoading($("#pgCreateAllButton"), $("#pgCreateAllSpinner"),
        $("#pgCreateAllButton .pg-create-all-icon"), $("#pgCreateAllLabel"),
        false, T.fileCreating, T.createAll);
      showError(T.createFailed || "The expenses could not be created. Please try again.");
    });
  }

  $("#pgCreateAllButton").addEventListener("click", createAllDetected);

  // ----------------------------------------------------------------- steps

  function pre(text) {
    var el = document.createElement("pre");
    el.className = "pg-pre mb-0";
    el.innerHTML = escapeHtml(text);
    return el;
  }

  function jsonPre(value) {
    try {
      return pre(JSON.stringify(value, null, 2));
    } catch (e) {
      return pre(String(value));
    }
  }

  function debugRow(label, value) {
    return '<div class="d-flex"><span class="pg-debug-key">' + escapeHtml(label) +
      '</span><span class="ms-2">' + escapeHtml(value) + "</span></div>";
  }

  function arrow() {
    var el = document.createElement("div");
    el.className = "pg-arrow text-center";
    el.innerHTML = "&darr;";
    return el;
  }

  function stepSection(title) {
    var el = document.createElement("div");
    el.className = "pg-step";
    var heading = document.createElement("div");
    heading.className = "pg-step-title";
    heading.textContent = title;
    el.appendChild(heading);
    return el;
  }

  function candidateAccordionTitle(candidate, index) {
    var description = candidate && (candidate.description || candidate.merchant);
    return (T.expenseN || "Expense %{n}").replace("%{n}", index + 1) + ": " + (description || "—");
  }

  function candidateAccordionItem(index, candidate, open) {
    var collapseId = "pgExpenseCollapse" + index;
    var item = document.createElement("div");
    item.className = "accordion-item";
    item.setAttribute("data-testid", "playground-expense-accordion");
    item.innerHTML =
      '<h2 class="accordion-header" id="pgExpenseHeading' + index + '">' +
      '<button class="accordion-button' + (open ? "" : " collapsed") + '" type="button"' +
      ' data-bs-toggle="collapse" data-bs-target="#' + collapseId + '"' +
      ' aria-expanded="' + (open ? "true" : "false") + '" aria-controls="' + collapseId + '"' +
      ' data-testid="playground-expense-accordion-toggle">' +
      escapeHtml(candidateAccordionTitle(candidate, index)) +
      "</button></h2>" +
      '<div id="' + collapseId + '" class="accordion-collapse collapse' + (open ? " show" : "") + '"' +
      ' aria-labelledby="pgExpenseHeading' + index + '">' +
      '<div class="accordion-body" data-testid="playground-expense-accordion-body"></div>' +
      "</div>";
    return item;
  }

  // Steps that belong to the whole run (input / ocr / stt), repeated inside
  // every gasto accordion as decided for the pipeline debug panel.
  function appendSharedSteps(body, steps) {
    var input = stepSection(T.stepInput);
    var inputEl = steps.input || {};
    input.appendChild(pre((inputEl.type || "") + (inputEl.text ? "\n\n" + inputEl.text : "") +
      (inputEl.image ? "\n\n" + inputEl.image : "")));
    body.appendChild(input);
    body.appendChild(arrow());

    var ocr = stepSection(T.stepOcr);
    if (steps.ocr && steps.ocr.applicable) {
      ocr.appendChild(pre(steps.ocr.text || ""));
    } else {
      ocr.appendChild(pre(T.ocrNotApplicable));
    }
    body.appendChild(ocr);
    body.appendChild(arrow());

    var stt = stepSection(T.stepStt);
    if (steps.stt && steps.stt.applicable) {
      if (steps.stt.error) {
        stt.appendChild(pre(steps.stt.error));
      } else {
        var sttEl = document.createElement("div");
        sttEl.innerHTML =
          debugRow("provider:", steps.stt.provider || "—") + debugRow("model:", steps.stt.model || "—") +
          debugRow("language:", steps.stt.language || "—") +
          debugRow("duration:", steps.stt.duration == null ? "—" : steps.stt.duration);
        stt.appendChild(sttEl);
        stt.appendChild(pre(steps.stt.text || ""));
      }
    } else {
      stt.appendChild(pre(T.ocrNotApplicable));
    }
    body.appendChild(stt);
    body.appendChild(arrow());
  }

  // Per-expense steps: extraction entry N, validation entry N and the
  // candidate verdict for that gasto. No normalization (not recorded anymore).
  function appendExpenseSteps(body, steps, index) {
    var extraction = stepSection(T.stepExtraction);
    var extractionStep = steps.extraction;
    // The text pipeline records the extraction entries array directly; the
    // vision path still wraps them in an { engine, raw } hash.
    var entries = Array.isArray(extractionStep) ? extractionStep : (extractionStep && extractionStep.raw);
    var engineText = extractionStep && extractionStep.engine ? T.engineLabel + ": " + extractionStep.engine : "";
    if (extractionStep && extractionStep.ai_strategy) {
      engineText += (engineText ? " · " : "") + strategyLabel(extractionStep.ai_strategy);
    }
    if (engineText) extraction.appendChild(pre(engineText));
    var entry = Array.isArray(entries) ? entries[index] : entries;
    if (entry != null) {
      extraction.appendChild(jsonPre(entry));
    } else {
      extraction.appendChild(pre(T.ocrNotApplicable));
    }
    body.appendChild(extraction);
    body.appendChild(arrow());

    var validation = stepSection(T.stepValidation);
    var validationStep = steps.validation;
    var validationEntry = Array.isArray(validationStep) ? validationStep[index] : validationStep;
    var checkHtml = "";
    if (validationEntry) {
      (validationEntry.checks || []).forEach(function (check) {
        checkHtml += '<div class="' + (check.passed ? "text-success" : "text-danger") + '">' +
          (check.passed ? "✓" : "✗") + " " + escapeHtml(check.label) + "</div>";
      });
      (validationEntry.errors || []).forEach(function (error) {
        checkHtml += '<div class="text-danger">' + escapeHtml(error) + "</div>";
      });
    }
    validation.innerHTML += checkHtml || "<em>—</em>";
    body.appendChild(validation);
    body.appendChild(arrow());

    var candidateStep = stepSection(T.stepCandidate);
    var valid = !!(validationEntry && validationEntry.valid);
    var candidateText = valid ? T.candidateReady : T.candidateInvalid;
    candidateStep.innerHTML += '<div class="' + (valid ? "text-success" : "text-danger") + ' fw-semibold">' +
      escapeHtml(candidateText) + "</div>";
    body.appendChild(candidateStep);
  }

  function refreshAccordionToggleIcon(container, icon) {
    var accordions = container.querySelectorAll(".accordion-collapse");
    if (!icon) return;
    var allOpen = accordions.length > 0 && Array.prototype.every.call(accordions, function (el) {
      return el.classList.contains("show");
    });
    icon.classList.toggle("ti-arrows-diagonal-minimize", allOpen);
    icon.classList.toggle("ti-arrows-maximize", !allOpen);
  }

  function wireAccordionToggle(container, toggle, icon) {
    var accordions = container.querySelectorAll(".accordion-collapse");
    toggle.classList.toggle("d-none", accordions.length === 0);
    toggle.onclick = function () {
      var expand = !Array.prototype.every.call(accordions, function (el) {
        return el.classList.contains("show");
      });
      accordions.forEach(function (el) {
        if (window.bootstrap && window.bootstrap.Collapse) {
          bootstrap.Collapse.getOrCreateInstance(el)[expand ? "show" : "hide"]();
        } else {
          el.classList.toggle("show", expand);
        }
      });
      refreshAccordionToggleIcon(container, icon);
    };
    refreshAccordionToggleIcon(container, icon);
  }

  function renderSteps(data) {
    var steps = data.steps || {};
    var candidates = data.candidates && data.candidates.length
      ? data.candidates
      : (data.candidate ? [data.candidate] : []);
    var container = $("#pgSteps");
    container.textContent = "";

    $("#pgDebugMeta").textContent = (data.engine ? T.engineLabel + ": " + data.engine : "") +
      (data.duration_ms != null ? (data.engine ? " · " : "") + T.durationLabel + ": " + data.duration_ms + " ms" : "");

    var accordion = document.createElement("div");
    accordion.className = "accordion";
    // Failed runs detect no expenses: still show the shared pipeline stages
    // in one accordion so the debug panel is never empty.
    var count = candidates.length || 1;
    for (var index = 0; index < count; index++) {
      var candidate = candidates[index] || null;
      var item = candidateAccordionItem(index, candidate, index === 0);
      var body = item.querySelector(".accordion-body");
      appendSharedSteps(body, steps);
      if (candidates.length) {
        appendExpenseSteps(body, steps, index);
      }
      accordion.appendChild(item);
    }
    container.appendChild(accordion);
    wireAccordionToggle(container, $("#pgStepsToggle"), $("#pgStepsToggleIcon"));
  }

  // ---------------------------------------------------------------- history
  // Runs are persisted server-side (ExpensePlaygroundRun). localStorage is
  // only a same-session fallback when the history request fails.

  function readLocalHistory() {
    try {
      var raw = localStorage.getItem(HISTORY_KEY);
      return raw ? JSON.parse(raw) : [];
    } catch (e) {
      return [];
    }
  }

  function writeLocalHistory(entries) {
    try {
      localStorage.setItem(HISTORY_KEY, JSON.stringify(entries.slice(0, 10)));
    } catch (e) { /* storage unavailable: history is best-effort */ }
  }

  function addHistoryEntry(entry) {
    var entries = readLocalHistory();
    entries.unshift(entry);
    writeLocalHistory(entries);
    renderHistory(entries);
  }

  function historyResultLabel(entry) {
    var c = entry.candidate || {};
    return (c.amount != null ? money(c.amount) : "—") + " " + (c.category_name || "");
  }

  function renderHistory(entries) {
    entries = entries || [];
    var body = $("#pgHistoryBody");
    body.textContent = "";
    $("#pgHistoryEmpty").classList.toggle("d-none", entries.length > 0);
    $("#pgClearHistory").classList.toggle("d-none", entries.length === 0);

    entries.forEach(function (entry, index) {
      var row = document.createElement("tr");
      row.className = "pg-history-row";
      row.setAttribute("data-testid", "playground-history-row");
      var result = entry.ok ? escapeHtml(historyResultLabel(entry)) : '<span class="text-danger">failed</span>';
      if (entry.expense_id) result += ' <i class="ti ti-circle-check text-success" title="expense created"></i>';
      row.innerHTML =
        '<td class="small">' + escapeHtml(new Date(entry.ts).toLocaleDateString()) + "</td>" +
        '<td class="small text-truncate et-maxw-220px">"' + escapeHtml(entry.label || "") + '"</td>' +
        '<td class="small">' + escapeHtml(entry.type) + "</td>" +
        '<td class="small">' + result + "</td>" +
        '<td class="small text-end">' + escapeHtml(formatConfidence(entry.confidence)) + "</td>";
      row.addEventListener("click", function () { restoreHistoryEntry(entries[index]); });
      body.appendChild(row);
    });
  }

  function restoreHistoryEntry(entry) {
    state.lastSteps = entry.steps;
    state.lastResult = entry;
    state.candidates = entry.candidates && entry.candidates.length
      ? entry.candidates
      : (entry.candidate ? [entry.candidate] : []);
    $("#pgDebug").classList.remove("d-none");
    renderSttSummary(entry.steps);
    renderSteps({ steps: entry.steps, engine: null, duration_ms: null, ok: entry.ok, candidates: state.candidates });
    if (state.candidates.length) {
      $("#pgResultErrors").classList.add("d-none");
      $("#pgResultWarnings").classList.add("d-none");
      renderCards(state.candidates, null);
      $("#pgResultEmpty").classList.add("d-none");
      $("#pgResult").classList.remove("d-none");
    }
  }

  // ---------------------------------------------------------- AI summary

  var STRATEGY_BADGES = {
    "deterministic": "text-bg-secondary",
    "cache": "text-bg-info",
    "cheap_ai": "text-bg-success",
    "strong_ai": "text-bg-warning"
  };

  function strategyLabel(strategy) {
    switch (strategy) {
    case "deterministic": return T.aiStrategyDeterministic;
    case "cache": return T.aiStrategyCache;
    case "cheap_ai": return T.aiStrategyCheap;
    case "strong_ai": return T.aiStrategyStrong;
    default: return strategy || "—";
    }
  }

  function strategyBadge(strategy) {
    return '<span class="badge ' + (STRATEGY_BADGES[strategy] || "text-bg-light") + '">' +
      escapeHtml(strategyLabel(strategy)) + "</span>";
  }

  function analyzeAiPerformance(data) {
    var perf = data.performance || {};
    var summary = data.summary || {};
    var parts = [];
    var avg = perf.average_latency_ms;
    if (avg != null) {
      var verdict = avg < 5000 ? T.aiAnalysisOk : (avg < 12000 ? T.aiAnalysisSlow : T.aiAnalysisBad);
      parts.push(verdict.replace("%{avg}", Math.round(avg)));
    }
    if (perf.average_tokens_per_second != null && perf.average_tokens_per_second < 30) {
      parts.push(T.aiAnalysisGeneration.replace("%{tps}", perf.average_tokens_per_second));
    }
    if (summary.ai_fallback_rate != null && summary.ai_fallback_rate > 0.3) {
      parts.push(T.aiAnalysisEscalation.replace("%{rate}", Math.round(summary.ai_fallback_rate * 100)));
    }
    if (perf.slowest_model && perf.slowest_model_latency_ms != null) {
      parts.push(T.aiAnalysisSlowestModel
        .replace("%{model}", perf.slowest_model)
        .replace("%{latency}", Math.round(perf.slowest_model_latency_ms)));
    }
    if (summary.failed_requests > 0) {
      parts.push(T.aiAnalysisErrors.replace("%{count}", summary.failed_requests));
    }
    return parts.slice(0, 2).join(" ");
  }

  function renderAiSummary(data) {
    var summary = data.summary || {};
    var perf = data.performance || {};
    var chips = $("#pgAiChips");
    chips.innerHTML = "";

    function chip(label, value) {
      var el = document.createElement("span");
      el.className = "badge text-bg-light";
      el.textContent = label + ": " + value;
      chips.appendChild(el);
    }

    chip(T.aiSummaryDeterministic, summary.deterministic_requests || 0);
    chip(T.aiSummaryCache, summary.cache_hits || 0);
    chip(T.aiSummaryCheap, summary.cheap_ai_requests || 0);
    chip(T.aiSummaryStrong, summary.strong_ai_requests || 0);
    chip(T.aiSummaryFallback, Math.round((summary.ai_fallback_rate || 0) * 100) + "%");
    if (summary.average_confidence != null) chip(T.aiSummaryConfidence, summary.average_confidence);
    chip(T.aiSummaryTokens, (summary.input_tokens || 0) + " / " + (summary.output_tokens || 0));
    if (perf.average_latency_ms != null) chip(T.aiAvgLatency, Math.round(perf.average_latency_ms) + " ms");
    if (perf.p95_latency_ms != null) chip(T.aiP95Latency, perf.p95_latency_ms + " ms");
    if (perf.average_tokens_per_second != null) chip(T.aiTokensPerSecond, perf.average_tokens_per_second);
    Object.keys(perf.latency_by_model || {}).forEach(function (model) {
      chip(model, Math.round(perf.latency_by_model[model]) + " ms");
    });

    var analysis = $("#pgAiAnalysis");
    var analysisText = analyzeAiPerformance(data);
    analysis.textContent = analysisText;
    analysis.classList.toggle("d-none", !analysisText);

    $("#pgAiCheapTier").textContent = T.aiSummaryCheapTier + ": " +
      (data.cheap_tier_enabled ? T.aiSummaryEnabled : T.aiSummaryDisabled);

    var rows = (data.recent || []).map(function (r) {
      var tr = document.createElement("tr");
      tr.className = "pg-ai-row";
      tr.setAttribute("data-testid", "playground-ai-row");
      var status = r.status === "ok" ? "" : (' <span class="badge text-bg-danger">' + escapeHtml(r.status) + "</span>");
      var escalated = r.escalated ? (' <span class="badge text-bg-warning">' + escapeHtml(T.aiSummaryEscalated) + "</span>") : "";
      var model = [ r.provider, r.model ].filter(Boolean).join("/");
      var conf = r.confidence == null ? "—" : Number(r.confidence).toFixed(2);
      var latency = r.latency_ms == null ? "—" : r.latency_ms + " ms";
      var tokens = (r.input_tokens == null && r.output_tokens == null)
        ? "—" : (r.input_tokens || 0) + " / " + (r.output_tokens || 0);
      var tps = r.tokens_per_second == null ? "—" : r.tokens_per_second;
      tr.innerHTML =
        "<td>" + strategyBadge(r.strategy) + status + escalated + "</td>" +
        '<td class="small">' + escapeHtml(r.task) + "</td>" +
        '<td class="small text-muted">' + escapeHtml(model || "—") + "</td>" +
        '<td class="small text-muted">' + escapeHtml(conf) + "</td>" +
        '<td class="small text-muted">' + escapeHtml(tokens) + "</td>" +
        '<td class="small text-muted">' + escapeHtml(tps) + "</td>" +
        '<td class="small text-muted text-end">' + escapeHtml(latency) + "</td>";

      // Per-call performance detail, shown when the row is clicked.
      var detail = document.createElement("tr");
      detail.className = "d-none pg-ai-detail";
      detail.setAttribute("data-testid", "playground-ai-call-detail");
      detail.innerHTML =
        '<td colspan="7">' +
        '<div class="border rounded p-2 bg-light">' +
        '<div class="small fw-semibold text-muted mb-1">' + escapeHtml(r.task) + " · " + escapeHtml(new Date(r.created_at).toLocaleString()) + "</div>" +
        debugRow(T.aiCallTotalTime + ":", latency) +
        debugRow(T.aiSummaryTokens + ":", tokens) +
        debugRow(T.aiTokensPerSecond + ":", tps) +
        debugRow("TTFT:", "—") +
        debugRow(T.aiGenerationTime + ":", "—") +
        debugRow(T.aiProviderModel + ":", model || "—") +
        (r.prompt && r.prompt.length
          ? '<div class="small fw-semibold text-muted mt-2 mb-1">' + escapeHtml(T.aiCallPrompt) + "</div>" +
            '<pre class="pg-pre mb-0 pg-ai-io">' + escapeHtml(
              r.prompt.map(function (message) { return "[" + message.role + "] " + message.content; }).join("\n\n")
            ) + "</pre>"
          : "") +
        (r.output
          ? '<div class="small fw-semibold text-muted mt-2 mb-1">' + escapeHtml(T.aiCallOutput) + "</div>" +
            '<pre class="pg-pre mb-0 pg-ai-io">' + escapeHtml(r.output) + "</pre>"
          : "") +
        "</div></td>";

      tr.addEventListener("click", function () { detail.classList.toggle("d-none"); });

      return [ tr, detail ];
    });

    var body = $("#pgAiBody");
    body.textContent = "";
    rows.forEach(function (pair) { pair.forEach(function (row) { body.appendChild(row); }); });
    $("#pgAiEmpty").classList.toggle("d-none", rows.length > 0);
  }

  function loadAiSummary() {
    fetch(form.dataset.aiSummaryUrl, {
      headers: { "Accept": "application/json", "X-CSRF-Token": csrfToken() }
    }).then(function (response) {
      if (!response.ok) throw new Error("ai_summary");
      return response.json();
    }).then(renderAiSummary).catch(function () { /* summary panel stays empty */ });
  }

  function loadHistory() {
    fetch(form.dataset.historyUrl, {
      headers: { "Accept": "application/json", "X-CSRF-Token": csrfToken() }
    }).then(function (response) {
      if (!response.ok) throw new Error("history");
      return response.json();
    }).then(function (data) {
      renderHistory((data.runs || []).map(function (run) {
        run.label = run.label || "";
        return run;
      }));
    }).catch(function () {
      renderHistory(readLocalHistory());
    });
  }

  $("#pgClearHistory").addEventListener("click", function () {
    writeLocalHistory([]);
    renderHistory([]);
  });

  // ------------------------------------------------------------------- init

  form.addEventListener("submit", function (event) {
    event.preventDefault();
    processInput();
  });

  renderHistory([]);
  loadHistory();
  loadAiSummary();
}

document.addEventListener("turbo:load", initializePlayground);
document.addEventListener("DOMContentLoaded", initializePlayground);
if (document.readyState !== "loading") initializePlayground();
