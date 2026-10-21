(function () {
  // Searchable category dropdown. The server renders a native <select> (kept
  // hidden so forms still submit it) next to a combobox that filters the
  // same options as you type.
  //
  // Public API on window.CategoryPicker:
  //   bind(container)   enhance a picker built at runtime; returns the picker
  //   value(select)     current value of a picker's select
  //   setValue(select, value)  pick a category from script, keeping the
  //                     visible label in sync

  var CONTAINER_SELECTOR = "[data-category-picker]";
  var OPTION_SELECTOR = "[role=option][data-value]";

  // Mirrors ActivityClassification.normalize_name so "publicos" matches
  // "Servicios públicos" and punctuation never blocks a match. The `u` flag
  // is what makes \p{L}/\p{N} read as "any letter/number"; without it the
  // class matches those literal characters instead and every query normalizes
  // to "" — the list would never filter.
  function normalize(text) {
    return String(text == null ? "" : text)
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .replace(/[^\p{L}\p{N}\s]+/gu, " ")
      .trim()
      .replace(/\s+/g, " ");
  }

  function CategoryPicker(container) {
    this.container = container;
    this.input = container.querySelector("[role=combobox]");
    this.listbox = container.querySelector("[role=listbox]");
    this.select = container.querySelector("select");
    this.toggle = container.querySelector("[data-category-picker-toggle]");
    this.emptyMessage = container.querySelector("[data-no-results]");
    this.feedback = container.querySelector("[data-required-message]");
    this.visibleOptions = [];
    this.activeIndex = -1;
  }

  CategoryPicker.prototype.options = function () {
    return Array.prototype.slice.call(this.listbox.querySelectorAll(OPTION_SELECTOR));
  };

  CategoryPicker.prototype.bind = function () {
    var self = this;

    this.input.addEventListener("input", function () {
      self.filter(self.input.value);
      self.open();
    });

    this.input.addEventListener("focus", function () {
      self.open();
    });

    this.input.addEventListener("keydown", function (event) {
      self.onKeydown(event);
    });

    this.input.addEventListener("blur", function () {
      // Clicking an option blurs the input first; defer so the click lands.
      window.setTimeout(function () { self.close(); }, 120);
    });

    if (this.toggle) {
      this.toggle.addEventListener("click", function () {
        if (self.isOpen()) {
          self.close();
        } else {
          self.open();
          self.input.focus();
        }
      });
    }

    this.listbox.addEventListener("mousedown", function (event) {
      var option = event.target.closest(OPTION_SELECTOR);
      if (option) {
        event.preventDefault();
        self.choose(option);
      }
    });

    // Keeps the visible label correct when a script (or a bulk update) sets
    // the select's value directly.
    this.select.addEventListener("change", function () {
      self.syncFromSelect();
    });

    var form = this.container.closest("form");
    if (form) {
      form.addEventListener("submit", function (event) {
        if (!self.validate()) event.preventDefault();
      });

      // form.reset() restores the select without firing change, so the
      // visible label and the highlighted option would keep the category
      // picked in a previous use of the form (modal create after edit).
      form.addEventListener("reset", function () {
        window.setTimeout(function () { self.syncFromSelect(); }, 0);
      });
    }

    this.syncFromSelect();
    this.filter("");
    return this;
  };

  CategoryPicker.prototype.isOpen = function () {
    return !this.listbox.hidden;
  };

  CategoryPicker.prototype.open = function () {
    if (this.input.disabled) return;

    this.listbox.hidden = false;
    this.input.setAttribute("aria-expanded", "true");
    this.toggleScrollContainer(true);
    this.renderActive();
  };

  CategoryPicker.prototype.close = function () {
    this.listbox.hidden = true;
    this.input.setAttribute("aria-expanded", "false");
    this.input.removeAttribute("aria-activedescendant");
    this.toggleScrollContainer(false);
    this.setActive(-1);
  };

  // A picker inside a scrollable table would have its listbox clipped by the
  // wrapper's overflow. Let it escape while open and restore scrolling after.
  CategoryPicker.prototype.toggleScrollContainer = function (open) {
    var wrapper = this.container.closest(".table-responsive");
    if (wrapper) wrapper.classList.toggle("table-responsive--picker-open", open);
  };

  // Filters every option by its server-rendered search text. The list keeps
  // its alphabetical DOM order; non-matching rows are simply hidden.
  CategoryPicker.prototype.filter = function (query) {
    var needle = normalize(query);
    var matches = 0;

    this.options().forEach(function (option) {
      var hit = needle === "" || normalize(option.dataset.search).indexOf(needle) !== -1;
      option.hidden = !hit;
      if (hit) matches += 1;
    });

    if (this.emptyMessage) {
      this.emptyMessage.hidden = matches > 0 || this.options().length === 0;
    }

    this.visibleOptions = this.options().filter(function (option) { return !option.hidden; });
    this.setActive(needle === "" ? -1 : 0);
  };

  CategoryPicker.prototype.onKeydown = function (event) {
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      if (!this.isOpen()) { this.open(); return; }
      var step = event.key === "ArrowDown" ? 1 : -1;
      var next = this.activeIndex + step;
      if (next < 0) next = this.visibleOptions.length - 1;
      this.setActive(next);
      return;
    }

    if (event.key === "Enter") {
      if (this.isOpen() && this.activeIndex >= 0) {
        event.preventDefault();
        this.choose(this.visibleOptions[this.activeIndex]);
      }
      return;
    }

    if (event.key === "Escape") {
      if (this.isOpen()) { event.preventDefault(); this.close(); }
      return;
    }

    if (event.key === "Backspace" && this.input.value === "") {
      this.clear();
    }
  };

  CategoryPicker.prototype.setActive = function (index) {
    if (this.activeIndex >= 0 && this.visibleOptions[this.activeIndex]) {
      var previous = this.visibleOptions[this.activeIndex];
      previous.classList.remove("category-picker__option--active");
      previous.removeAttribute("data-active");
    }

    if (index >= this.visibleOptions.length) index = this.visibleOptions.length - 1;
    if (index < 0) {
      this.activeIndex = -1;
      this.input.removeAttribute("aria-activedescendant");
      return;
    }

    this.activeIndex = index;
    var option = this.visibleOptions[index];
    option.classList.add("category-picker__option--active");
    option.setAttribute("data-active", "true");
    this.input.setAttribute("aria-activedescendant", option.id);
    if (option.scrollIntoView) option.scrollIntoView({ block: "nearest" });
  };

  CategoryPicker.prototype.renderActive = function () {
    if (this.activeIndex >= 0) this.setActive(this.activeIndex);
  };

  // The blank option ("Todas las Categorías" in filters) is a value, not a
  // selection: it clears the box so the placeholder reads through instead of
  // leaving copyable text in the input.
  CategoryPicker.prototype.choose = function (option) {
    this.select.value = option.dataset.value;
    this.input.value = option.dataset.value === "" ? "" : option.textContent.trim();
    this.hideFeedback();
    this.close();
    this.filter("");
    this.select.dispatchEvent(new Event("change", { bubbles: true }));
  };

  CategoryPicker.prototype.clear = function () {
    this.select.value = "";
    this.input.value = "";
    this.hideFeedback();
    this.close();
    this.select.dispatchEvent(new Event("change", { bubbles: true }));
  };

  CategoryPicker.prototype.optionFor = function (value) {
    var wanted = String(value == null ? "" : value);
    return this.options().filter(function (option) {
      return option.dataset.value === wanted;
    })[0];
  };

  // Reads the select and repaints the visible label, so external writes to
  // the select never leave a stale category name in the box. A blank value
  // leaves the input empty: the placeholder is text, never copyable content.
  CategoryPicker.prototype.syncFromSelect = function () {
    var option = this.optionFor(this.select.value);
    this.input.value = option && option.dataset.value !== "" ? option.textContent.trim() : "";
    this.clearActive();
    if (option) {
      option.setAttribute("aria-selected", "true");
    }
    this.options().forEach(function (each) {
      if (each !== option) each.setAttribute("aria-selected", "false");
    });
  };

  CategoryPicker.prototype.clearActive = function () {
    this.options().forEach(function (option) {
      option.classList.remove("category-picker__option--active");
      option.removeAttribute("data-active");
    });
    this.activeIndex = -1;
  };

  CategoryPicker.prototype.hideFeedback = function () {
    this.input.classList.remove("is-invalid");
    if (this.feedback) this.feedback.hidden = true;
  };

  CategoryPicker.prototype.validate = function () {
    if (this.container.dataset.required !== "true" || this.select.value) return true;

    this.input.classList.add("is-invalid");
    if (this.feedback) this.feedback.hidden = false;
    this.open();
    this.input.focus();
    return false;
  };

  var instances = new WeakMap();

  function forNode(node) {
    if (!node) return null;
    var container = node.matches && node.matches(CONTAINER_SELECTOR)
      ? node
      : node.closest(CONTAINER_SELECTOR);
    if (!container) return null;

    if (!instances.has(container)) instances.set(container, new CategoryPicker(container));
    return instances.get(container);
  }

  function bindAll(root) {
    var scope = root || document;
    var containers = scope.querySelectorAll(CONTAINER_SELECTOR);
    Array.prototype.forEach.call(containers, function (container) {
      if (container.dataset.categoryPickerBound === "true") return;
      container.dataset.categoryPickerBound = "true";
      forNode(container).bind();
    });
  }

  document.addEventListener("turbo:load", function () { bindAll(); });
  document.addEventListener("DOMContentLoaded", function () { bindAll(); });
  if (document.readyState !== "loading") bindAll();

  window.CategoryPicker = {
    bind: function (container) {
      return forNode(container);
    },
    value: function (select) {
      var picker = forNode(select);
      return picker ? picker.select.value : (select ? select.value : "");
    },
    setValue: function (select, value) {
      var picker = forNode(select);
      if (!picker) return;
      if (value === "" || value == null) {
        picker.clear();
        return;
      }
      var option = picker.optionFor(value);
      if (option) picker.choose(option);
    },
    // The visible control, for scripts that focus or flag the field. The
    // select itself is hidden, so styling or focusing it would be invisible.
    input: function (select) {
      var picker = forNode(select);
      return picker ? picker.input : null;
    },
    setInvalid: function (select, invalid) {
      var input = window.CategoryPicker.input(select);
      if (input) input.classList.toggle("is-invalid", !!invalid);
    },
    focus: function (select) {
      var input = window.CategoryPicker.input(select);
      if (input) input.focus();
    }
  };
})();
