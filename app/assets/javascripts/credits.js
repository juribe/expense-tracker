// Credit savings panel ("Ayúdame a ahorrar").
//
// "Comparar" POSTs the form (see the credits/quick route) so the params never
// end up in the address bar, and the answer is just the savings panel — no full
// page rebuild. The results re-render when the goal changes too: picking a
// different objetivo (radio or "Elegir esta opción") re-submits the form so the
// server re-prioritizes the headline. Turbo is not loaded in this app, so this
// is plain fetch, the same approach as debt_capacity.js.
(function () {
  function panel() {
    return document.querySelector("[data-testid='credit-quick']");
  }

  function setLoading(submit, on) {
    if (!submit) return;

    if (on) {
      submit.dataset.quickPrevious = submit.innerHTML;
      submit.disabled = true;
      submit.innerHTML = '<span class="spinner-border spinner-border-sm me-1"></span>' +
        (submit.dataset.quickLoading || "");
    } else if (submit.dataset.quickPrevious) {
      submit.innerHTML = submit.dataset.quickPrevious;
      submit.disabled = false;
      delete submit.dataset.quickPrevious;
    }
  }

  function swap(html) {
    var current = panel();
    if (!current) return;

    current.outerHTML = html;
    var fresh = panel();
    if (fresh && window.MoneyInputs) window.MoneyInputs.init(fresh);
  }

  function revealResults() {
    var results = document.querySelector("#quick-results");
    if (!results) return;
    results.scrollIntoView({ behavior: "smooth", block: "start" });
    results.focus({ preventScroll: true });
  }

  function request(form) {
    var submit = form.querySelector("[data-quick-submit]");
    var amount = form.querySelector("[data-money-input]");
    // Match the no-JS submit: send the amount with es-CO separators already
    // normalized so the server measures savings from the same number.
    if (amount && window.MoneyInputs) {
      amount.value = window.MoneyInputs.sanitizeValue(amount.value);
    }

    setLoading(submit, true);

    fetch(form.getAttribute("action"), {
      method: "POST",
      body: new FormData(form),
      headers: { "Accept": "text/html", "X-Requested-With": "XMLHttpRequest" },
      credentials: "same-origin"
    })
      .then(function (response) {
        if (!response.ok) throw new Error("HTTP " + response.status);
        return response.text();
      })
      .then(function (html) {
        swap(html);
        revealResults();
      })
      .catch(function () {
        setLoading(submit, false);
      });
  }

  document.addEventListener("submit", function (event) {
    var form = event.target.closest("[data-quick-form]");
    if (!form) return;

    event.preventDefault();
    request(form);
  });

  // Changing the objetivo re-prioritizes the results (only once they exist;
  // before that the goal is just staged for "Comparar").
  document.addEventListener("change", function (event) {
    var goal = event.target.closest("[data-quick-form] input[name='goal']");
    if (!goal) return;

    var form = goal.closest("[data-quick-form]");
    if (document.querySelector("#quick-results")) request(form);
  });

  // "Elegir esta opción" and the recommendation link select that goal.
  document.addEventListener("click", function (event) {
    var choice = event.target.closest("[data-quick-goal]");
    if (!choice) return;

    event.preventDefault();
    var form = document.querySelector("[data-quick-form]");
    var goal = form && form.querySelector("input[name='goal'][value='" + choice.dataset.quickGoal + "']");
    if (!goal) return;

    goal.checked = true;
    request(form);
  });
})();
