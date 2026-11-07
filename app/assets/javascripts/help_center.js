// Help center search and article rating.
// Search degrades to a normal GET /ayuda?q=... without JavaScript.
(function () {
  "use strict";

  function csrfToken() {
    var meta = document.querySelector("meta[name='csrf-token']");
    return meta ? meta.getAttribute("content") : "";
  }

  function debounce(fn, wait) {
    var timer = null;
    return function () {
      var args = arguments;
      var context = this;
      clearTimeout(timer);
      timer = setTimeout(function () {
        fn.apply(context, args);
      }, wait);
    };
  }

  function textElement(tag, className, text) {
    var element = document.createElement(tag);
    if (className) element.className = className;
    element.textContent = text || "";
    return element;
  }

  function clearNode(node) {
    while (node.firstChild) node.removeChild(node.firstChild);
  }

  function initSearch() {
    document.querySelectorAll("[data-help-search-form]").forEach(function (form) {
      if (form.dataset.helpSearchReady === "true") return;
      form.dataset.helpSearchReady = "true";

      var input = form.querySelector("[data-help-search-input]");
      var clearButton = form.querySelector("[data-help-search-clear]");
      var section = document.querySelector("[data-help-search-results-section]");
      var results = section ? section.querySelector("[data-help-search-results]") : null;
      var controller = null;

      if (!input || !section || !results) return;

      function labels() {
        return {
          kicker: section.dataset.helpResultsKicker || "RESULTADOS",
          heading: section.dataset.helpResultsHeading || "Artículos que coinciden con tu búsqueda.",
          empty: section.dataset.helpResultsEmpty || "No encontramos artículos para esa búsqueda.",
          clear: section.dataset.helpResultsClear || "Limpiar búsqueda"
        };
      }

      function showSection() {
        section.hidden = false;
      }

      function hideSection() {
        section.hidden = true;
      }

      function setClearVisibility() {
        if (!clearButton) return;
        clearButton.hidden = input.value.trim().length === 0;
      }

      function showSearching(query) {
        var copy = labels();
        clearNode(results);
        showSection();

        var head = document.createElement("div");
        head.className = "help-results__head";
        head.appendChild(textElement("p", "help-eyebrow", copy.kicker));
        head.appendChild(textElement("h2", null, copy.heading));
        head.appendChild(textElement("p", "help-results__meta", "Buscando “" + query + "”…"));
        results.appendChild(head);
      }

      function showEmpty(query) {
        var copy = labels();
        clearNode(results);
        showSection();

        var head = document.createElement("div");
        head.className = "help-results__head";
        head.appendChild(textElement("p", "help-eyebrow", copy.kicker));
        head.appendChild(textElement("h2", null, copy.heading));
        head.appendChild(textElement("p", "help-results__meta", "0 resultados para “" + query + "”"));
        results.appendChild(head);

        var empty = document.createElement("div");
        empty.className = "help-empty";
        empty.appendChild(textElement("p", null, copy.empty));

        var clear = textElement("a", "help-link", copy.clear);
        clear.href = "/ayuda";
        empty.appendChild(clear);

        var contact = textElement("a", "help-link", "Contáctanos");
        contact.href = "/contact";
        empty.appendChild(contact);
        results.appendChild(empty);
      }

      function showResults(query, payload) {
        var copy = labels();
        var items = Array.isArray(payload.results) ? payload.results : [];
        clearNode(results);
        showSection();

        var head = document.createElement("div");
        head.className = "help-results__head";
        head.appendChild(textElement("p", "help-eyebrow", copy.kicker));
        head.appendChild(textElement("h2", null, copy.heading));
        head.appendChild(textElement("p", "help-results__meta",
          items.length + (items.length === 1 ? " resultado" : " resultados") + " para “" + query + "”"));
        results.appendChild(head);

        if (items.length === 0) {
          showEmpty(query);
          return;
        }

        var list = document.createElement("ul");
        list.className = "help-result-list";

        items.forEach(function (item) {
          var listItem = document.createElement("li");
          var url = String(item.url || "");
          var link = document.createElement("a");
          link.className = "help-result";
          link.href = url.charAt(0) === "/" ? url : "/ayuda";
          link.appendChild(textElement("span", "help-result__category", item.category || ""));
          link.appendChild(textElement("strong", null, item.title || ""));
          link.appendChild(textElement("span", "help-result__summary", item.summary || ""));
          listItem.appendChild(link);
          list.appendChild(listItem);
        });

        results.appendChild(list);
      }

      function clearResults() {
        if (controller) {
          controller.abort();
          controller = null;
        }
        clearNode(results);
        hideSection();
      }

      function search(query) {
        var term = query.trim();
        if (term.length < 2) {
          clearResults();
          return;
        }

        if (controller) controller.abort();
        controller = window.AbortController ? new AbortController() : null;

        showSearching(term);

        fetch("/ayuda/buscar?q=" + encodeURIComponent(term), {
          headers: { "Accept": "application/json" },
          credentials: "same-origin",
          signal: controller ? controller.signal : undefined
        })
          .then(function (response) {
            if (!response.ok) throw new Error("search_failed");
            return response.json();
          })
          .then(function (payload) {
            showResults(term, payload);
          })
          .catch(function (error) {
            if (error && error.name === "AbortError") return;
            showEmpty(term);
          })
          .finally(function () {
            controller = null;
          });
      }

      var debouncedSearch = debounce(function () {
        search(input.value);
      }, 280);

      input.addEventListener("input", function () {
        setClearVisibility();
        debouncedSearch();
      });

      form.addEventListener("submit", function (event) {
        event.preventDefault();
        setClearVisibility();
        search(input.value);
      });

      if (clearButton) {
        clearButton.addEventListener("click", function () {
          input.value = "";
          setClearVisibility();
          clearResults();
          input.focus();
        });
      }

      setClearVisibility();
    });
  }

  function initRatings() {
    document.querySelectorAll("[data-help-rating]").forEach(function (container) {
      if (container.dataset.helpRatingReady === "true") return;
      container.dataset.helpRatingReady = "true";

      var buttons = Array.prototype.slice.call(container.querySelectorAll("[data-help-rating-value]"));
      var status = container.querySelector("[data-help-rating-status]");
      var pageId = container.dataset.helpRatingPage;
      var thanksText = container.dataset.helpRatingThanks || "Gracias por tu valoración.";
      var errorText = container.dataset.helpRatingError || "No pudimos registrar tu valoración.";

      if (!buttons.length || !status || !pageId) return;

      function setBusy(busy) {
        buttons.forEach(function (button) {
          button.disabled = busy;
        });
      }

      buttons.forEach(function (button) {
        button.addEventListener("click", function (event) {
          if (button.disabled) return;

          event.preventDefault();
          event.stopPropagation();
          setBusy(true);
          status.className = "help-feedback__status";
          status.textContent = "Enviando…";

          fetch("/ayuda/valoracion", {
            method: "POST",
            credentials: "same-origin",
            headers: {
              "Accept": "application/json",
              "Content-Type": "application/json",
              "X-CSRF-Token": csrfToken()
            },
            body: JSON.stringify({
              page_id: pageId,
              helpful: button.dataset.helpRatingValue === "true"
            })
          })
            .then(function (response) {
              return response.json().then(function (data) {
                return { ok: response.ok, data: data };
              });
            })
            .then(function (result) {
              if (result.ok) {
                status.className = "help-feedback__status is-success";
                status.textContent = result.data.message || thanksText;
              } else {
                status.className = "help-feedback__status is-error";
                status.textContent = result.data.error || errorText;
                setBusy(false);
              }
            })
            .catch(function () {
              status.className = "help-feedback__status is-error";
              status.textContent = errorText;
              setBusy(false);
            });
        });
      });
    });
  }

  function init() {
    initSearch();
    initRatings();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
