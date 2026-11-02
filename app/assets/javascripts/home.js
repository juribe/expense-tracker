document.addEventListener("DOMContentLoaded", function () {
  // Close mobile menu when clicking hash links
  document.querySelectorAll('a[href^="#"]').forEach(function (a) {
    a.addEventListener("click", function () {
      var navLinks = document.getElementById("navLinks");
      if (navLinks) navLinks.classList.remove("open");
    });
  });

  // Mobile menu toggle
  var menuToggle = document.querySelector("[data-menu-toggle]");
  if (menuToggle) {
    menuToggle.addEventListener("click", function () {
      var navLinks = document.getElementById("navLinks");
      if (navLinks) navLinks.classList.toggle("open");
    });
  }

  // Home: flow tabs demo
  document.querySelectorAll(".flow-tab").forEach(function (tab) {
    tab.addEventListener("click", function () {
      var key = tab.dataset.flow;
      document.querySelectorAll(".flow-tab").forEach(function (x) {
        x.classList.toggle("active", x === tab);
      });
      document.querySelectorAll(".demo-flow").forEach(function (flow) {
        var active = flow.dataset.demo === key;
        flow.classList.toggle("active", active);
        if (active) {
          flow.querySelectorAll(".demo-step").forEach(function (step) {
            step.style.animation = "none";
            void step.offsetHeight;
            step.style.animation = "";
          });
        }
      });
    });
  });

  // Pricing modal logic
  var backdrop = document.getElementById("modalBackdrop");
  if (backdrop) {
    var selectedPlan = "";
    var selectedAmount = "";
    var selectedBilling = "";
    var selectedMethod = "card";
    var modalMode = "trial";

    function openTrial() {
      modalMode = "trial";
      document.getElementById("modalTitle").textContent = "Comienza tu prueba gratis";
      document.getElementById("modalDesc").textContent = "Disfruta 30 días de acceso completo a Yogasto. No necesitas tarjeta y no te cobraremos automáticamente.";
      document.getElementById("methodChoices").style.display = "none";
      document.getElementById("modalAction").textContent = "Activar prueba gratis";
      document.getElementById("modalFoot").textContent = "Sin tarjeta · Sin cobros · Sin compromisos";
      document.getElementById("successNote").classList.remove("show");
      backdrop.classList.add("show");
    }

    function openCheckout(plan, amount, billing) {
      modalMode = "checkout";
      selectedPlan = plan;
      selectedAmount = amount;
      selectedBilling = billing;
      selectedMethod = "card";
      document.getElementById("modalTitle").textContent = "Continúa con tu plan " + plan.toLowerCase();
      document.getElementById("modalDesc").textContent = "Plan " + plan + " · $" + amount + " COP" + (billing === "month" ? " por mes" : " por 12 meses") + ". Elige cómo quieres realizar tu pago.";
      document.getElementById("methodChoices").style.display = "block";
      document.getElementById("cardHint").textContent = billing === "month" ? "Renovación mensual con tu autorización" : "Un solo pago por 12 meses";
      document.getElementById("pseHint").textContent = "Pago manual desde tu banco";
      document.getElementById("modalAction").textContent = "Continuar con tarjeta";
      document.getElementById("modalFoot").textContent = billing === "month" ? "Con PSE, la renovación es manual." : "Pago único · Sin renovación automática";
      document.getElementById("successNote").classList.remove("show");
      document.querySelectorAll(".method").forEach(function (m) {
        m.classList.toggle("selected", m.dataset.method === "card");
      });
      backdrop.classList.add("show");
    }

    function selectMethod(el) {
      document.querySelectorAll(".method").forEach(function (m) {
        m.classList.remove("selected");
      });
      el.classList.add("selected");
      selectedMethod = el.dataset.method;
      document.getElementById("modalAction").textContent = "Continuar con " + (selectedMethod === "card" ? "tarjeta" : "PSE");
    }

    function modalContinue() {
      var note = document.getElementById("successNote");
      note.textContent = modalMode === "trial" ? "Prototipo: aquí se conectaría la acción para crear la prueba gratuita de 30 días en Yogasto." : "Prototipo: aquí se redirigiría al checkout del proveedor con el plan y medio de pago seleccionados.";
      note.classList.add("show");
    }

    function closeModal() {
      backdrop.classList.remove("show");
    }

    function backdropClose(e) {
      if (e.target === backdrop) closeModal();
    }

    document.querySelectorAll("[data-open-trial]").forEach(function (btn) {
      btn.addEventListener("click", openTrial);
    });
    document.querySelectorAll("[data-open-checkout]").forEach(function (btn) {
      btn.addEventListener("click", function () {
        openCheckout(btn.dataset.plan, btn.dataset.amount, btn.dataset.billing);
      });
    });
    document.querySelectorAll(".method").forEach(function (m) {
      m.addEventListener("click", function () {
        selectMethod(m);
      });
    });
    var modalAction = document.getElementById("modalAction");
    if (modalAction) modalAction.addEventListener("click", modalContinue);
    var closeBtn = document.querySelector(".modal .close");
    if (closeBtn) closeBtn.addEventListener("click", closeModal);
    backdrop.addEventListener("click", backdropClose);
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape") closeModal();
    });

    // FAQ accordion
    document.querySelectorAll(".faq-q").forEach(function (btn) {
      btn.addEventListener("click", function () {
        var item = btn.closest(".faq-item");
        var wasOpen = item.classList.contains("open");
        item.classList.toggle("open");
        btn.setAttribute("aria-expanded", String(!wasOpen));
      });
    });
  }
});
