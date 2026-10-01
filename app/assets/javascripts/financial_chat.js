// Financial Chat: real-time conversation over Action Cable.
//
// Events (broadcast by FinancialChatChannel / FinancialAnalysisService):
//   message_received    { message }  - persisted user message (ack)
//   assistant_processing               - show the thinking placeholder
//   assistant_delta     { delta }     - incremental answer text
//   assistant_completed { message }   - final answer (content is safe HTML)
//   assistant_failed    { error }     - inline error with retry
(function () {
  "use strict";

  document.addEventListener("DOMContentLoaded", function () {
    var page = document.getElementById("financialChat");
    if (!page) return;

    var scroll = document.getElementById("chatScroll");
    var input = document.getElementById("chatInput");
    var sendButton = document.getElementById("chatSend");
    var reconnecting = document.getElementById("chatReconnecting");
    var emptyState = document.getElementById("chatEmptyState");
    var sending = false; // POST in flight
    var streaming = false; // assistant response in progress
    var lastUserMessageId = null;
    var streamingEl = null; // live assistant bubble elements

    function csrfToken() {
      var meta = document.querySelector("meta[name='csrf-token']");
      return meta ? meta.content : "";
    }

    function scrollToBottom() {
      scroll.scrollTop = scroll.scrollHeight;
    }

    function updateSendButton() {
      var hasText = input.value.trim().length > 0;
      sendButton.disabled = !hasText || sending || streaming;
    }

    function addUserBubble(content, state) {
      var row = document.createElement("div");
      row.className = "chat-row chat-row-user";
      row.setAttribute("data-chat-state", state);

      var bubble = document.createElement("div");
      bubble.className = "chat-bubble-user";
      var text = document.createElement("p");
      text.className = "mb-1";
      text.textContent = content;
      bubble.appendChild(text);

      var meta = document.createElement("small");
      meta.className = "chat-time";
      meta.textContent = state === "sending" ? "enviando…" : currentTime();
      if (state === "sending") {
        meta.setAttribute("data-role", "status");
        bubble.setAttribute("data-pending", "true");
      }
      bubble.appendChild(meta);

      row.appendChild(bubble);
      scroll.insertBefore(row, reconnecting);
      scrollToBottom();
      return bubble;
    }

    function currentTime() {
      return new Date().toLocaleTimeString("es-CO", { hour: "2-digit", minute: "2-digit" });
    }

    function markUserMessagePersisted(bubble) {
      if (!bubble) return;
      bubble.removeAttribute("data-pending");
      bubble.setAttribute("data-chat-state", "persisted");
      var status = bubble.querySelector("small[data-role='status']");
      if (status) status.textContent = currentTime();
    }

    function thinkingEl() {
      var el = document.createElement("div");
      el.className = "chat-row chat-row-assistant";
      el.setAttribute("data-chat-thinking", "true");

      var avatar = document.createElement("div");
      avatar.className = "chat-avatar bg-primary text-white";
      avatar.innerHTML = "<i class='bi bi-piggy-bank'></i>";

      var bubble = document.createElement("div");
      bubble.className = "chat-bubble-assistant";

      var label = document.createElement("span");
      label.className = "chat-thinking";
      label.textContent = page.dataset.thinkingText;

      var dots = document.createElement("span");
      dots.className = "chat-thinking__dots";
      dots.innerHTML = "<span></span><span></span><span></span>";

      bubble.appendChild(label);
      bubble.appendChild(dots);
      el.appendChild(avatar);
      el.appendChild(bubble);
      scroll.insertBefore(el, reconnecting);
      scrollToBottom();
      return el;
    }

    function startStreaming() {
      streaming = true;
      updateSendButton();

      var thinking = scroll.querySelector("[data-chat-thinking='true']");
      if (thinking) thinking.remove();

      var row = document.createElement("div");
      row.className = "chat-row chat-row-assistant";
      row.setAttribute("data-chat-streaming", "true");

      var avatar = document.createElement("div");
      avatar.className = "chat-avatar bg-primary text-white";
      avatar.innerHTML = "<i class='bi bi-piggy-bank'></i>";

      var bubble = document.createElement("div");
      bubble.className = "chat-bubble-assistant chat-bubble-streaming";
      bubble.setAttribute("data-role", "text");

      row.appendChild(avatar);
      row.appendChild(bubble);
      scroll.insertBefore(row, reconnecting);
      streamingEl = { row: row, bubble: bubble };
    }

    function appendDelta(delta) {
      if (!streamingEl) startStreaming();
      streamingEl.bubble.textContent += delta;
      scrollToBottom();
    }

    function completeStreaming(message) {
      if (streamingEl) {
        streamingEl.row.remove();
        streamingEl = null;
      }
      var row = document.createElement("div");
      row.className = "chat-row chat-row-assistant";
      row.setAttribute("data-message-id", message.id);

      var avatar = document.createElement("div");
      avatar.className = "chat-avatar bg-primary text-white";
      avatar.innerHTML = "<i class='bi bi-piggy-bank'></i>";

      var bubble = document.createElement("div");
      bubble.className = "chat-bubble-assistant chat-bubble-rich";
      bubble.innerHTML = message.content;

      row.appendChild(avatar);
      row.appendChild(bubble);
      scroll.insertBefore(row, reconnecting);
      streaming = false;
      updateSendButton();
      scrollToBottom();
    }

    function failStreaming(error) {
      if (streamingEl) {
        streamingEl.row.remove();
        streamingEl = null;
      }
      var thinking = scroll.querySelector("[data-chat-thinking='true']");
      if (thinking) thinking.remove();

      var row = document.createElement("div");
      row.className = "chat-row chat-row-assistant";
      row.setAttribute("data-chat-failed", "true");

      var avatar = document.createElement("div");
      avatar.className = "chat-avatar bg-primary text-white";
      avatar.innerHTML = "<i class='bi bi-piggy-bank'></i>";

      var bubble = document.createElement("div");
      bubble.className = "chat-error";
      bubble.innerHTML =
        "<i class='bi bi-exclamation-triangle'></i><span>" + escapeHtml(error) + "</span>";

      var retry = document.createElement("button");
      retry.type = "button";
      retry.className = "btn btn-sm btn-outline-primary";
      retry.textContent = "Reintentar";
      retry.addEventListener("click", function () {
        row.remove();
        resend();
      });

      bubble.appendChild(retry);
      row.appendChild(avatar);
      row.appendChild(bubble);
      scroll.insertBefore(row, reconnecting);
      streaming = false;
      updateSendButton();
      scrollToBottom();
    }

    function escapeHtml(text) {
      var div = document.createElement("div");
      div.textContent = text;
      return div.innerHTML;
    }

    function sendMessage(content) {
      content = content.trim();
      if (!content || sending || streaming) return;

      sending = true;
      updateSendButton();
      if (emptyState) {
        emptyState.remove();
        emptyState = null;
      }
      var bubble = addUserBubble(content, "sending");

      fetch(page.dataset.sendUrl, {
        method: "POST",
        headers: {
          "X-CSRF-Token": csrfToken(),
          "Content-Type": "application/json",
          Accept: "application/json"
        },
        body: JSON.stringify({ content: content })
      })
        .then(function (response) {
          sending = false;
          if (!response.ok) {
            markUserMessageFailed(bubble);
            return response.json().catch(function () { return {}; });
          }
          return response.json();
        })
        .then(function (body) {
          sending = false;
          updateSendButton();
          if (body && body.message) {
            lastUserMessageId = body.message.id;
            markUserMessagePersisted(bubble);
          }
        })
        .catch(function () {
          sending = false;
          updateSendButton();
          markUserMessageFailed(bubble);
        });

      input.value = "";
      autoGrow();
      updateSendButton();
    }

    function markUserMessageFailed(bubble) {
      if (!bubble) return;
      bubble.setAttribute("data-pending", "failed");
      var status = bubble.querySelector("small[data-role='status']");
      if (status) status.textContent = "no se pudo enviar";
    }

    // Re-enqueue analysis for the last failed question.
    function resend() {
      var failedRow = scroll.querySelector("[data-chat-failed='true']");
      var rows = scroll.querySelectorAll(".chat-row-user");
      var lastUserRow = rows.length ? rows[rows.length - 1] : null;
      if (!lastUserRow) return;

      var content = lastUserRow.querySelector("p").textContent;
      if (failedRow) failedRow.remove();
      sending = true;
      updateSendButton();

      var bubble = addUserBubble(content, "sending");
      fetch(page.dataset.sendUrl, {
        method: "POST",
        headers: {
          "X-CSRF-Token": csrfToken(),
          "Content-Type": "application/json",
          Accept: "application/json"
        },
        body: JSON.stringify({ content: content })
      })
        .then(function (response) {
          sending = false;
          updateSendButton();
          if (response.ok) {
            markUserMessagePersisted(bubble);
            lastUserRow.remove();
          }
        })
        .catch(function () {
          sending = false;
          updateSendButton();
        });
    }

    function autoGrow() {
      input.style.height = "auto";
      input.style.height = Math.min(input.scrollHeight, 160) + "px";
    }

    // Event wiring

    input.addEventListener("keydown", function (event) {
      if (event.key === "Enter" && !event.shiftKey) {
        event.preventDefault();
        sendMessage(input.value);
      }
    });

    input.addEventListener("input", function () {
      autoGrow();
      updateSendButton();
    });

    document.getElementById("chatComposer").addEventListener("submit", function (event) {
      event.preventDefault();
      sendMessage(input.value);
    });

    Array.prototype.forEach.call(document.querySelectorAll(".chat-suggestion"), function (chip) {
      chip.addEventListener("click", function () {
        sendMessage(chip.dataset.suggestion);
      });
    });

    ActionCable.createConsumer().subscriptions.create("FinancialChatChannel", {
      connected: function () {
        reconnecting.hidden = true;
      },

      disconnected: function () {
        reconnecting.hidden = false;
      },

      received: function (event) {
        switch (event.event) {
          case "message_received":
            if (event.message && event.message.id) lastUserMessageId = event.message.id;
            break;
          case "assistant_processing":
            thinkingEl();
            break;
          case "assistant_delta":
            appendDelta(event.delta || "");
            break;
          case "assistant_completed":
            completeStreaming(event.message);
            break;
          case "assistant_failed":
            failStreaming(event.error || "No se pudo procesar tu pregunta.");
            break;
        }
      }
    });

    scrollToBottom();
    updateSendButton();
  });
})();
