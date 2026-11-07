// Privacy policy table of contents: highlights the section currently in view.
// A passive scroll listener with requestAnimationFrame keeps this cheap, and
// anchor scrolling still works without JavaScript.
(function () {
  "use strict";

  function init() {
    var toc = document.querySelector("[data-privacy-toc]");
    var sections = Array.prototype.slice.call(document.querySelectorAll("[data-privacy-section]"));
    if (!toc || sections.length === 0) return;

    var links = Array.prototype.slice.call(toc.querySelectorAll("[data-privacy-toc-link]"));
    var linksByAnchor = {};
    links.forEach(function (link) {
      linksByAnchor[link.getAttribute("data-privacy-toc-link")] = link;
    });

    function setActive(anchor) {
      links.forEach(function (link) {
        var active = link === linksByAnchor[anchor];
        link.classList.toggle("is-active", active);
        if (active) {
          link.setAttribute("aria-current", "true");
        } else {
          link.removeAttribute("aria-current");
        }
      });
    }

    function updateActive() {
      var threshold = window.innerHeight * 0.3;
      var current = sections[0];

      sections.forEach(function (section) {
        if (section.getBoundingClientRect().top <= threshold) {
          current = section;
        }
      });

      if (current) setActive(current.getAttribute("data-privacy-anchor"));
    }

    var ticking = false;
    function scheduleUpdate() {
      if (ticking) return;
      ticking = true;
      window.requestAnimationFrame(function () {
        updateActive();
        ticking = false;
      });
    }

    window.addEventListener("scroll", scheduleUpdate, { passive: true });
    window.addEventListener("resize", scheduleUpdate);
    updateActive();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
