// Savings opportunities (Pro).
// Financial values are precomputed by Rails and carried in data attributes;
// this module only reads them, formats them and keeps the scenario in sync.
(() => {
  const money = (value) =>
    "$" + new Intl.NumberFormat("es-CO", { maximumFractionDigits: 0 }).format(Math.round(Number(value) || 0));

  const csrfToken = () => document.querySelector('meta[name="csrf-token"]')?.content;

  const perMonthLabel = () => document.querySelector("[data-so-page]")?.dataset.soPerMonth || "mes";

  let polling = false;

  const pendingNote = () => document.querySelector("[data-so-pending-note]");
  const errorNote = () => document.querySelector("[data-so-analysis-error]");
  const refreshButton = () => document.querySelector("[data-so-refresh-button]");

  function setPendingNote(visible) {
    const note = pendingNote();
    if (note) note.hidden = !visible;

    if (visible) {
      const error = errorNote();
      if (error) error.hidden = true;
    }
  }

  function setErrorNote() {
    const note = pendingNote();
    if (note) note.hidden = true;

    const error = errorNote();
    if (error) error.hidden = false;
  }

  function setRefreshBusy(busy) {
    const button = refreshButton();
    if (!button) return;

    const label = button.querySelector("span");
    if (label && !button.dataset.soOriginalLabel) button.dataset.soOriginalLabel = label.textContent;
    if (label) {
      label.textContent = busy
        ? button.dataset.soRefreshingLabel || button.dataset.soOriginalLabel
        : button.dataset.soOriginalLabel;
    }

    button.disabled = busy;
  }

  function bindChoices() {
    document.querySelectorAll("[data-so-choice-group]").forEach((group) => {
      if (group.dataset.soBound === "true") return;
      group.dataset.soBound = "true";

      group.querySelectorAll("[data-so-choice]").forEach((choice) => {
        choice.addEventListener("click", () => {
          group.querySelectorAll("[data-so-choice]").forEach((item) => item.classList.remove("selected"));
          choice.classList.add("selected");

          const output = document.getElementById(choice.dataset.soSavingTarget);
          if (output) output.textContent = money(choice.dataset.soSaving);
        });
      });
    });
  }

  function bindSimulator() {
    const form = document.querySelector("[data-so-scenario-form]");
    if (!form || form.dataset.soBound === "true") return;
    form.dataset.soBound = "true";

    const rows = Array.from(form.querySelectorAll("[data-so-sim-row]"));
    const totalOutput = form.querySelector("[data-so-total]");
    const sixOutput = form.querySelector("[data-so-six]");
    const twelveOutput = form.querySelector("[data-so-twelve]");
    const summaryOutput = document.querySelector("[data-so-sim-summary]");
    const submit = form.querySelector("[data-so-goal-submit]");

    const update = () => {
      let total = 0;

      rows.forEach((row) => {
        const range = row.querySelector("[data-so-range]");
        const steps = JSON.parse(row.dataset.soSteps || "{}");
        const percentage = String(range.value);
        const saving = Number(steps[percentage] || 0);

        row.querySelector("[data-so-percent]").textContent = `${percentage}%`;
        const savingOutput = row.querySelector("[data-so-saving] b");
        if (savingOutput) savingOutput.textContent = money(saving);
        const hidden = row.querySelector("[data-so-hidden]");
        if (hidden) hidden.value = percentage;

        total += saving;
      });

      if (totalOutput) totalOutput.textContent = money(total);
      if (sixOutput) sixOutput.textContent = money(total * 6);
      if (twelveOutput) twelveOutput.textContent = money(total * 12);
      if (summaryOutput) summaryOutput.textContent = `${money(total)} / ${perMonthLabel()}`;
      if (submit) submit.disabled = total <= 0;
    };

    rows.forEach((row) => row.querySelector("[data-so-range]")?.addEventListener("input", update));
    update();
  }

  function startPolling(url, attempt = 0, onTimeout = null) {
    if (!url) return;

    if (attempt === 0) {
      if (polling) return;
      polling = true;
    }

    const retry = () => {
      if (attempt >= 40) {
        polling = false;
        if (onTimeout) onTimeout();
        return;
      }

      setTimeout(() => startPolling(url, attempt + 1, onTimeout), 3000);
    };

    fetch(url, { headers: { Accept: "application/json" }, credentials: "same-origin" })
      .then((response) => response.json())
      .then((payload) => {
        if (payload.state === "ready" || payload.state === "failed") {
          polling = false;
          window.location.reload();
          return;
        }

        retry();
      })
      .catch(retry);
  }

  function bindRefresh() {
    const form = document.querySelector("[data-so-refresh-form]");
    if (!form || form.dataset.soBound === "true") return;
    form.dataset.soBound = "true";

    const statusUrl = form.dataset.soStatusUrl;

    const finishWithError = () => {
      setRefreshBusy(false);
      setPendingNote(false);
      setErrorNote();
    };

    form.addEventListener("submit", (event) => {
      event.preventDefault();
      setRefreshBusy(true);
      setPendingNote(true);

      fetch(form.action, {
        method: "POST",
        headers: { Accept: "application/json", "X-CSRF-Token": csrfToken() },
        credentials: "same-origin",
        body: new FormData(form)
      })
        .then((response) => response.json())
        .then((payload) => {
          if (payload.state === "pending") {
            startPolling(statusUrl, 0, finishWithError);
          } else {
            setRefreshBusy(false);
            setPendingNote(false);
          }
        })
        .catch(() => {
          // Without JS-assisted refresh the plain form still works.
          if (form.dataset.soSubmitting === "true") return;
          form.dataset.soSubmitting = "true";
          form.submit();
        });
    });
  }

  function init() {
    bindChoices();
    bindSimulator();
    bindRefresh();

    const status = document.querySelector("[data-so-analysis-status]");
    if (status && status.dataset.soPending === "true" && !polling) {
      setPendingNote(true);
      setRefreshBusy(true);
      startPolling(status.dataset.soStatusUrl, 0, () => {
        setRefreshBusy(false);
        setPendingNote(false);
        setErrorNote();
      });
    }
  }

  document.addEventListener("DOMContentLoaded", init);
  document.addEventListener("turbo:load", init);
})();
