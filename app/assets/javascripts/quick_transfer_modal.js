(function() {
  var modalEl = document.getElementById('quick-transfer-modal');
  if (!modalEl) return;
  var body = document.getElementById('quick_transfer_body');
  var titleText = document.getElementById('quick-transfer-modal-title-text');
  if (modalEl.dataset.quickBound) return;
  modalEl.dataset.quickBound = "1";

  function injectForm(html) {
    body.innerHTML = html;
    // innerHTML does not execute scripts: re-create them (pocket mode's
    // goal sync) and re-bind money masks + forms on the fresh markup.
    Array.prototype.forEach.call(body.querySelectorAll('script'), function(old) {
      var fresh = document.createElement('script');
      fresh.textContent = old.textContent;
      old.replaceWith(fresh);
    });
    if (window.MoneyInputs) MoneyInputs.init(body);
    var form = body.querySelector('form[data-testid="quick-transfer-form"]');
    if (form) bindSubmit(form);
  }

  // Ajax submission so failures stay in the modal. A successful request is a
  // redirect; read manually so the target page (and its flash) is rendered by
  // a real navigation instead of being consumed here.
  function bindSubmit(form) {
    var submitter = form.querySelector('[type="submit"]');
    form.addEventListener('submit', function(event) {
      event.preventDefault();
      submitter.disabled = true;
      fetch(form.getAttribute('action'), {
        method: 'POST',
        body: new FormData(form),
        redirect: 'manual',
        credentials: 'same-origin',
        headers: { 'X-Requested-With': 'XMLHttpRequest' }
      }).then(function(response) {
        if (response.type === 'opaqueredirect') {
          var returnTo = form.querySelector('input[name="return_to"]');
          window.location.href = (returnTo && returnTo.value) || '/transfers';
          return;
        }
        if ((response.status >= 400 && response.status < 500) || response.ok) {
          return response.text().then(function(html) { injectForm(html); });
        }
        throw new Error('HTTP ' + response.status);
      }).catch(function() {
        body.insertAdjacentHTML('afterbegin',
          '<div class="alert alert-warning"><i class="ti ti-alert-triangle me-2"></i>No se pudo enviar el formulario. Revisa tu conexión e inténtalo de nuevo.</div>');
        submitter.disabled = false;
      });
    });
  }

  function loadForm(url) {
    body.innerHTML = '<div class="text-secondary small py-3"><i class="ti ti-loader me-1"></i>Cargando...</div>';
    fetch(url, { headers: { "Accept": "text/html", "X-Requested-With": "XMLHttpRequest" }, credentials: "same-origin" })
      .then(function(response) {
        // A redirected resolve (e.g. a guard) answered with a full page:
        // navigate instead of shoving it into the modal body.
        if (response.redirected) throw new Error("redirected");
        if (!response.ok) throw new Error("HTTP " + response.status);
        return response.text();
      })
      .then(injectForm)
      .catch(function() {
        window.location.href = url;
      });
  }

  modalEl.addEventListener('show.bs.modal', function(event) {
    var button = event.relatedTarget;
    if (!button) return;
    var title = button.getAttribute('data-title');
    var src = button.getAttribute('data-src');
    if (title) titleText.textContent = title;
    if (src) loadForm(src);
  });
})();
