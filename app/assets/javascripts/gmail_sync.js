(function () {
  // --- Async Gmail sync auto-refresh --------------------------------------
  // A sync runs as a background job; the settings page offers no inline
  // result until it finishes. When the user clicks "Sincronizar", we remember
  // that a sync is pending (in sessionStorage) and, on the page that loads
  // after the redirect, poll the sync_status endpoint. Once the connection is
  // no longer "syncing" and a summary is available, we stop and refresh so
  // the fresh imports / last_synced / suggestions appear without a manual reload.
  var SYNC_POLL_KEY = "gmailSyncPending";
  var SYNC_POLL_INTERVAL = 2000;
  var SYNC_POLL_TIMEOUT = 5 * 60 * 1000; // give up after 5 minutes
  var syncPollerRunning = false;

  function gmailSyncStatusPath() {
    var btn = document.querySelector("[data-sync-status-path]");
    return btn ? btn.getAttribute("data-sync-status-path") : null;
  }

  function startSyncPoller() {
    // One poller at a time: the submit listener and the turbo:load resume
    // both may try to start one on the same navigation.
    if (syncPollerRunning) return;

    var statusPath = gmailSyncStatusPath();
    if (!statusPath) return;
    syncPollerRunning = true;

    var startedAt = Date.now();
    var timer = setInterval(function () {
      fetch(statusPath, { headers: { "Accept": "application/json" } })
        .then(function (res) { return res.ok ? res.json() : null; })
        .then(function (state) {
          if (!state) return; // transient error: keep polling

          var done = !state.syncing && state.summary;
          var timedOut = Date.now() - startedAt > SYNC_POLL_TIMEOUT;
          if (!done && !timedOut) return;

          clearInterval(timer);
          syncPollerRunning = false;
          try { sessionStorage.removeItem(SYNC_POLL_KEY); } catch (_) {}
          if (window.Turbo) { window.Turbo.visit(window.location.href); }
          else { window.location.reload(); }
        })
        .catch(function () { /* network blip: keep polling until timeout */ });
    }, SYNC_POLL_INTERVAL);
  }

  document.addEventListener("submit", function (e) {
    var btn = e.target.querySelector && e.target.querySelector("[data-sync-status-path]");
    if (!btn) return;
    try { sessionStorage.setItem(SYNC_POLL_KEY, "1"); } catch (_) {}
    startSyncPoller();
  });

  // If we arrive with a pending sync, start polling right away — no manual
  // reload. Turbo Drive renders redirects WITHOUT a full page load, so this
  // must re-run on every Turbo visit (turbo:load), not just at script eval.
  function resumePendingSyncPolling() {
    var hasPendingSync = false;
    try { hasPendingSync = sessionStorage.getItem(SYNC_POLL_KEY) === "1"; } catch (_) {}
    if (hasPendingSync && gmailSyncStatusPath()) {
      startSyncPoller();
    }

    // Page rendered while a sync is running (arrived mid-scan): poll until it
    // finishes and refresh so the results show up without a manual reload.
    if (document.querySelector("[data-sync-in-progress]")) {
      startSyncPoller();
    }
  }

  resumePendingSyncPolling();
  document.addEventListener("DOMContentLoaded", resumePendingSyncPolling);
  document.addEventListener("turbo:load", resumePendingSyncPolling);
  document.addEventListener("turbo:render", resumePendingSyncPolling);
})();
