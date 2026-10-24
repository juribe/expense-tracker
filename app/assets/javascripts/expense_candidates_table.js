  (function() {
    var payloadEl = document.querySelector("[data-candidates-table-payload]");
    var payload = payloadEl ? JSON.parse(payloadEl.dataset.candidatesTablePayload) : {};
    var $ = function(sel) { return document.querySelector(sel); };
    var $$ = function(sel) { return document.querySelectorAll(sel); };

    function selectedIds() {
      var seen = {};
      Array.from($$("tr[data-id]"))
        .filter(function(el) { var cb = el.querySelector(".row-check"); return cb && cb.checked; })
        .forEach(function(el) { seen[el.dataset.id] = true; });
      return Object.keys(seen);
    }

    function updateBulk() {
      var n = selectedIds().length;
      var has = n > 0;
      var bar = $("#bulkBar");
      if (bar) bar.style.display = has ? "flex" : "none";
      if ($("#bulkCount")) $("#bulkCount").textContent = n + " " + payload.selected_label;
      ["bulkCategory", "bulkSource", "bulkConfirm", "bulkDiscard"].forEach(function(id) {
        var el = $("#" + id);
        if (el) el.disabled = !has;
      });
    }

    function openBulkConfirmModal(focusField) {
      var ids = selectedIds();
      if (!ids.length) return;
      var n = ids.length;
      var word = n === 1 ? "candidato" : "candidatos";
      $("#bulkCandidateIds").value = ids.join(",");
      $("#bulkConfirmDescription").textContent = n + " " + word + " " + payload.will_be_confirmed;
      CategoryPicker.setValue($("#bulkCategorySelect"), "");
      $("#bulkSourceSelect").value = "";
      $("#confirmBulkSubmit").disabled = false;
      var modal = bootstrap.Modal.getOrCreateInstance("#bulkConfirmModal");
      modal.show();
      if (focusField === "bulkCategorySelect") {
        CategoryPicker.focus($("#bulkCategorySelect"));
      } else if (focusField) {
        document.getElementById(focusField).focus();
      }
    }

    document.addEventListener("change", function(e) {
      if (e.target.matches(".row-check, #selectAll")) {
        if (e.target.id === "selectAll") {
          Array.from($$(".row-check")).forEach(function(c) { c.checked = e.target.checked; });
        }
        updateBulk();
      }
    });

    function bulkDiscardSelected() {
      var ids = selectedIds();
      if (!ids.length) return;
      var n = ids.length;
      var word = n === 1 ? "candidato" : "candidatos";
      var message = n + " " + word + " " + payload.will_be_discarded + " " + payload.discard_undo_hint;
      if (!window.confirm(message)) return;
      var form = document.createElement("form");
      form.method = "post";
      form.action = payload.bulk_discard_url;
      var csrf = document.querySelector('meta[name="csrf-token"]');
      if (csrf) {
        var csrfInput = document.createElement("input");
        csrfInput.type = "hidden";
        csrfInput.name = "authenticity_token";
        csrfInput.value = csrf.content;
        form.appendChild(csrfInput);
      }
      var idsInput = document.createElement("input");
      idsInput.type = "hidden";
      idsInput.name = "candidate_ids";
      idsInput.value = ids.join(",");
      form.appendChild(idsInput);
      document.body.appendChild(form);
      form.submit();
    }

    document.addEventListener("click", function(e) {
      if (e.target.id === "bulkConfirm" || e.target.closest("#bulkConfirm")) {
        openBulkConfirmModal();
      } else if (e.target.id === "bulkCategory" || e.target.closest("#bulkCategory")) {
        openBulkConfirmModal("bulkCategorySelect");
      } else if (e.target.id === "bulkSource" || e.target.closest("#bulkSource")) {
        openBulkConfirmModal("bulkSourceSelect");
      } else if (e.target.id === "bulkDiscard" || e.target.closest("#bulkDiscard")) {
        bulkDiscardSelected();
      }
    });

    $("#bulkConfirmForm").addEventListener("submit", function() {
      var btn = $("#confirmBulkSubmit");
      btn.disabled = true;
      btn.innerHTML = '<span class="spinner-border spinner-border-sm me-1" role="status" aria-hidden="true"></span>' + payload.creating_label;
    });

    updateBulk();
  })();
