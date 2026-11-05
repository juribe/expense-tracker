(() => {
  const overlay = document.querySelector("[data-financial-habit-overlay]");
  if (!overlay || overlay.dataset.bound === "true") return;

  overlay.dataset.bound = "true";
  const drawer = overlay.querySelector(".fh-drawer");
  const content = overlay.querySelector("[data-financial-habit-drawer-content]");

  const close = () => {
    overlay.classList.remove("show");
    document.body.classList.remove("fh-drawer-open");
    window.setTimeout(() => {
      overlay.hidden = true;
      content.innerHTML = "";
    }, 220);
  };

  const open = async (url) => {
    content.innerHTML = '<div class="fh-drawer-loading">Cargando análisis…</div>';
    overlay.hidden = false;
    document.body.classList.add("fh-drawer-open");
    requestAnimationFrame(() => overlay.classList.add("show"));

    try {
      const response = await fetch(url, { headers: { Accept: "text/html" } });
      if (!response.ok) throw new Error("No se pudo cargar el análisis");

      const html = await response.text();
      const doc = new DOMParser().parseFromString(html, "text/html");
      const detail = doc.querySelector(".financial-habit-detail");
      content.innerHTML = detail ? detail.outerHTML : '<div class="fh-drawer-loading">No encontramos ese análisis.</div>';

      const back = content.querySelector(".fhd-back");
      if (back) {
        back.removeAttribute("href");
        back.addEventListener("click", (event) => {
          event.preventDefault();
          close();
        });
      }

      content.querySelectorAll('a[href="/financial_habits"]').forEach((link) => {
        link.addEventListener("click", (event) => {
          event.preventDefault();
          close();
        });
      });

      const closeButton = drawer.querySelector("[data-financial-habit-close]");
      if (closeButton) closeButton.focus();
    } catch (_error) {
      content.innerHTML = '<div class="fh-drawer-loading">No pudimos cargar el análisis. Intenta de nuevo.</div>';
    }
  };

  document.addEventListener("click", (event) => {
    const link = event.target.closest("[data-financial-habit-detail-link]");
    if (link) {
      event.preventDefault();
      open(link.href);
      return;
    }

    if (event.target.closest("[data-financial-habit-close]")) {
      event.preventDefault();
      close();
      return;
    }

    if (event.target === overlay) close();
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && !overlay.hidden) close();
  });
})();