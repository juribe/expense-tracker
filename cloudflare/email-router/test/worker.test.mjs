import test from "node:test";
import assert from "node:assert/strict";
import { createHash, createHmac } from "node:crypto";

import worker from "../src/index.js";

const RECIPIENT = "receive+user1@samyreplies.com";
const SECRET = "worker-test-secret";
const RAILS_URL = "https://example.test/webhooks/email";
const originalFetch = globalThis.fetch;

function rawEmail() {
  return new TextEncoder().encode(
    "From: Banco <notificaciones@bank.example>\r\n" +
    `To: ${RECIPIENT}\r\n` +
    "Subject: Compra aprobada\r\n" +
    "Message-ID: <worker-test@example.com>\r\n" +
    "\r\nCompra aprobada por $48.500",
  );
}

function messageFor(raw, overrides = {}) {
  return {
    from: "notificaciones@bank.example",
    to: RECIPIENT,
    rawSize: raw.length,
    raw: new Response(raw).body,
    rejected: null,
    setReject(reason) {
      this.rejected = reason;
    },
    ...overrides,
  };
}

function env(overrides = {}) {
  return {
    INBOUND_EMAIL_SECRET: SECRET,
    RAILS_INBOUND_EMAIL_URL: RAILS_URL,
    ALLOWED_RECIPIENTS: RECIPIENT,
    MAX_EMAIL_BYTES: "1048576",
    REQUEST_TIMEOUT_MS: "1000",
    ...overrides,
  };
}

function restoreFetch(t) {
  t.after(() => {
    globalThis.fetch = originalFetch;
  });
}

test("forwards the raw MIME with a compatible HMAC signature", async (t) => {
  restoreFetch(t);
  let captured = null;
  globalThis.fetch = async (url, options) => {
    captured = { url, options };
    return new Response(null, { status: 202 });
  };

  const raw = rawEmail();
  const message = messageFor(raw);
  await worker.email(message, env(), {});

  assert.equal(captured.url, RAILS_URL);
  assert.equal(captured.options.method, "POST");
  assert.equal(Buffer.from(captured.options.body).toString("utf8"), Buffer.from(raw).toString("utf8"));
  assert.equal(message.rejected, null);

  const headers = captured.options.headers;
  const timestamp = headers["X-Cloudflare-Email-Timestamp"];
  const bodyHash = createHash("sha256").update(raw).digest("hex");
  const expected = createHmac("sha256", SECRET)
    .update(`${timestamp}\n${RECIPIENT}\n${bodyHash}`)
    .digest("hex");

  assert.equal(headers["Content-Type"], "message/rfc822");
  assert.equal(headers["X-Cloudflare-Email-Recipient"], RECIPIENT);
  assert.equal(headers["X-Cloudflare-Email-Signature"], expected);
});

test("accepts the base receive address alongside plus subaddresses", async (t) => {
  restoreFetch(t);
  let captured = null;
  globalThis.fetch = async (url, options) => {
    captured = { url, options };
    return new Response(null, { status: 202 });
  };

  const message = messageFor(rawEmail(), { to: "receive@samyreplies.com" });
  await worker.email(
    message,
    env({ ALLOWED_RECIPIENTS: "receive@samyreplies.com,receive+*@samyreplies.com" }),
    {},
  );

  assert.equal(message.rejected, null);
  assert.equal(captured.options.headers["X-Cloudflare-Email-Recipient"], "receive@samyreplies.com");
});

test("accepts a plus subaddress with a wildcard allowlist", async (t) => {
  restoreFetch(t);
  let captured = null;
  globalThis.fetch = async (url, options) => {
    captured = { url, options };
    return new Response(null, { status: 202 });
  };

  const message = messageFor(rawEmail(), { to: "receive+user2@samyreplies.com" });
  await worker.email(message, env({ ALLOWED_RECIPIENTS: "receive+*@samyreplies.com" }), {});

  assert.equal(message.rejected, null);
  assert.equal(captured.options.headers["X-Cloudflare-Email-Recipient"], "receive+user2@samyreplies.com");
});

test("rejects an unexpected recipient without calling Rails", async (t) => {
  restoreFetch(t);
  let called = false;
  globalThis.fetch = async () => {
    called = true;
    return new Response(null, { status: 202 });
  };

  const message = messageFor(rawEmail(), { to: "receive+other@samyreplies.com" });
  await worker.email(message, env(), {});

  assert.equal(message.rejected, "Recipient not allowed");
  assert.equal(called, false);
});

test("rejects oversized messages before reading the body", async (t) => {
  restoreFetch(t);
  let called = false;
  globalThis.fetch = async () => {
    called = true;
    return new Response(null, { status: 202 });
  };

  const raw = rawEmail();
  const message = messageFor(raw);
  await worker.email(message, env({ MAX_EMAIL_BYTES: "10" }), {});

  assert.equal(message.rejected, "Message too large");
  assert.equal(called, false);
});

test("turns a permanent Rails rejection into setReject", async (t) => {
  restoreFetch(t);
  globalThis.fetch = async () => new Response(null, { status: 422 });

  const message = messageFor(rawEmail());
  await worker.email(message, env(), {});

  assert.equal(message.rejected, "Inbound email rejected");
});

test("throws on a temporary Rails failure so Cloudflare can retry", async (t) => {
  restoreFetch(t);
  globalThis.fetch = async () => new Response(null, { status: 503 });

  await assert.rejects(
    () => worker.email(messageFor(rawEmail()), env(), {}),
    /temporarily rejected/,
  );
});
