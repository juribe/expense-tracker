// Cloudflare Email Worker for Expense Tracker inbound email.
//
// Email Routing invokes the `email` handler (not `fetch`). The Worker forwards
// the original RFC 5322/MIME bytes to Rails, authenticated with a timestamped
// HMAC over the recipient and the SHA-256 of the raw body.

const encoder = new TextEncoder();
const DEFAULT_MAX_BYTES = 10 * 1024 * 1024;
const MAX_ALLOWED_BYTES = 25 * 1024 * 1024;
const DEFAULT_TIMEOUT_MS = 15_000;

function normalizedRecipient(value) {
  return String(value || "").trim().toLowerCase();
}

function allowedRecipients(env) {
  return String(env.ALLOWED_RECIPIENTS || "")
    .split(",")
    .map((value) => normalizedRecipient(value))
    .filter(Boolean);
}

function recipientAllowed(recipient, patterns) {
  return patterns.some((pattern) => {
    if (pattern === recipient) return true;
    if (!pattern.includes("*")) return false;

    const escaped = pattern
      .replace(/[.+?^${}()|[\]\\]/g, "\\$&")
      .replace(/\*/g, ".*");
    return new RegExp(`^${escaped}$`, "i").test(recipient);
  });
}

function maxBytes(env) {
  const configured = Number(env.MAX_EMAIL_BYTES || DEFAULT_MAX_BYTES);
  if (!Number.isFinite(configured) || configured <= 0) return DEFAULT_MAX_BYTES;

  return Math.min(configured, MAX_ALLOWED_BYTES);
}

function timeoutMs(env) {
  const configured = Number(env.REQUEST_TIMEOUT_MS || DEFAULT_TIMEOUT_MS);
  return Number.isFinite(configured) && configured > 0 ? configured : DEFAULT_TIMEOUT_MS;
}

function toHex(buffer) {
  return [...new Uint8Array(buffer)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function sha256Hex(bytes) {
  return toHex(await crypto.subtle.digest("SHA-256", bytes));
}

async function hmacHex(secret, value) {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    [ "sign" ],
  );
  return toHex(await crypto.subtle.sign("HMAC", key, encoder.encode(value)));
}

async function fetchWithTimeout(url, options, milliseconds) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), milliseconds);

  try {
    return await fetch(url, { ...options, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

function permanentRejection(status) {
  return status >= 400 && status < 500 && status !== 408 && status !== 429;
}

export default {
  async email(message, env, _ctx) {
    const recipient = normalizedRecipient(message.to);
    const recipients = allowedRecipients(env);

    if (recipients.length === 0) {
      console.error("Inbound email worker is missing ALLOWED_RECIPIENTS");
      message.setReject("Inbound email is not configured");
      return;
    }

    if (!recipientAllowed(recipient, recipients)) {
      console.warn(`Rejected inbound email for unexpected recipient=${recipient}`);
      message.setReject("Recipient not allowed");
      return;
    }

    const limit = maxBytes(env);
    if (!Number.isFinite(message.rawSize) || message.rawSize > limit) {
      console.warn(`Rejected oversized inbound email to=${recipient}`);
      message.setReject("Message too large");
      return;
    }

    const secret = env.INBOUND_EMAIL_SECRET;
    const railsUrl = env.RAILS_INBOUND_EMAIL_URL;
    if (!secret || !railsUrl) {
      throw new Error("Inbound email worker is not configured");
    }

    try {
      const raw = new Uint8Array(await new Response(message.raw).arrayBuffer());
      if (raw.byteLength > limit) {
        message.setReject("Message too large");
        return;
      }

      const timestamp = Math.floor(Date.now() / 1000).toString();
      const bodyHash = await sha256Hex(raw);
      const signature = await hmacHex(secret, `${timestamp}\n${recipient}\n${bodyHash}`);

      const response = await fetchWithTimeout(
        railsUrl,
        {
          method: "POST",
          headers: {
            "Content-Type": "message/rfc822",
            "X-Cloudflare-Email-Timestamp": timestamp,
            "X-Cloudflare-Email-Recipient": recipient,
            "X-Cloudflare-Email-Signature": signature,
            "X-Cloudflare-Email-From": String(message.from || ""),
          },
          body: raw,
        },
        timeoutMs(env),
      );

      const status = response.status;
      if (response.body) await response.body.cancel();

      if (response.ok) {
        console.log(`Inbound email accepted to=${recipient} status=${status}`);
        return;
      }

      if (permanentRejection(status)) {
        console.warn(`Rails permanently rejected inbound email to=${recipient} status=${status}`);
        message.setReject("Inbound email rejected");
        return;
      }

      throw new Error(`Rails temporarily rejected inbound email with status ${status}`);
    } catch (error) {
      // Throwing tells Cloudflare delivery to retry; the Worker itself never loops.
      console.error(`Inbound email forwarding failed: ${error?.name || "Error"}`);
      throw error;
    }
  },
};
