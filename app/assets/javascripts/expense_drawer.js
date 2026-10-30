// Expense drawer: an offcanvas that fetches an expense's show page
// (a layout-less fragment) and shows it anywhere in the app.
//
// Triggers declare their URLs via data attributes:
//   <a href="#" data-expense-drawer
//      data-view-url="/expenses/1"
//      data-edit-url="/expenses/1/edit"
//      data-delete-url="/expenses/1">...</a>
(function () {
  "use strict";

  var DRAWER_ID = "expenseDrawer";

  function $(sel) { return document.querySelector(sel); }

  function csrfToken() {
    var meta = document.querySelector('meta[name="csrf-token"]');
    return meta ? meta.content : "";
  }

  function setBusy(busy) {
    var edit = $("#expenseDrawerEdit");
    var del = $("#expenseDrawerDelete");
    [edit, del].forEach(function (el) {
      if (!el) return;
      el.disabled = busy;
      el.classList.toggle("disabled", busy);
    });
  }

  function open(options) {
    var body = $("#expenseDrawerBody");
    if (!body || !options.viewUrl) return;

    body.innerHTML = '<div class="text-center text-muted py-4">' +
      '<div class="spinner-border spinner-border-sm" role="status">' +
      '<span class="visually-hidden">Cargando&hellip;</span></div></div>';
    setBusy(true);

    var edit = $("#expenseDrawerEdit");
    var del = $("#expenseDrawerDelete");
    if (edit) edit.href = options.editUrl || "#";
    if (del) {
      del.disabled = !options.deleteUrl;
      del.dataset.deleteUrl = options.deleteUrl || "";
    }

    fetch(options.viewUrl, { headers: { "Accept": "text/html" } })
      .then(function (res) { return res.text(); })
      .then(function (html) {
        body.innerHTML = html;
        setBusy(false);
        bootstrap.Offcanvas.getOrCreateInstance("#" + DRAWER_ID).show();
      })
      .catch(function () {
        body.innerHTML = '<div class="alert alert-danger m-3 mb-0">No se pudo cargar el gasto.</div>';
        setBusy(false);
        bootstrap.Offcanvas.getOrCreateInstance("#" + DRAWER_ID).show();
      });
  }

  function submitDelete(url) {
    var form = document.createElement("form");
    form.method = "post";
    form.action = url;
    form.innerHTML =
      '<input type="hidden" name="_method" value="delete">' +
      '<input type="hidden" name="authenticity_token" value="' + csrfToken() + '">';
    document.body.appendChild(form);
    form.requestSubmit();
  }

  document.addEventListener("click", function (e) {
    var trigger = e.target.closest("[data-expense-drawer]");
    if (trigger) {
      e.preventDefault();
      open({
        viewUrl: trigger.dataset.viewUrl,
        editUrl: trigger.dataset.editUrl,
        deleteUrl: trigger.dataset.deleteUrl
      });
      return;
    }

    if (e.target.id === "expenseDrawerDelete") {
      var url = e.target.dataset.deleteUrl;
      if (!url) return;
      Dialog.confirm("¿Eliminar gasto? Esta acción no se puede deshacer.", { title: "¿Eliminar gasto?", confirmLabel: "Eliminar", variant: "danger" }).then(function (confirmed) {
        if (confirmed) submitDelete(url);
      });
    }
  });

  window.ExpenseDrawer = { open: open };
})();
