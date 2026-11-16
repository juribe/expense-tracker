# frozen_string_literal: true

require "test_helper"

module ErrorReporting
  class RollbarPayloadSanitizerTest < ActiveSupport::TestCase
    SENSITIVE_MESSAGE = <<~MESSAGE.squish
      Payment failed for user@example.com card 4111 1111 1111 1111
      with Authorization: Bearer abc.def.ghi and password=hunter2 for amount 1500000
    MESSAGE

    def sanitize(payload)
      RollbarPayloadSanitizer.call(payload: payload)
    end

    def default_payload
      {
        data: {
          environment: "production",
          code_version: "abc123",
          request: {
            url: "https://app.example.com/expenses?email=user@example.com&amount=1500000",
            method: "POST",
            request_id: "req-123",
            user_ip: "203.0.113.10",
            params: {
              controller: "expenses",
              action: "create",
              expense: {
                description: "Compra secreta",
                amount: "1500000",
                card_number: "4111111111111111"
              }
            },
            GET: { search: "user@example.com" },
            POST: { expense: { description: "Compra secreta" } },
            body: "{\"expense\":{\"description\":\"Compra secreta\"}}",
            cookies: { session: "session-token" },
            session: { user_id: "user-1" },
            headers: {
              Authorization: "Bearer secret-token",
              Cookie: "session=secret",
              "User-Agent": "RSpec"
            }
          },
          person: {
            id: "3f0c1c0e-6d8d-4a5e-9a7c-1e0f6f3c2a11",
            email: "user@example.com",
            username: "financial-user"
          },
          body: {
            trace: {
              exception: { class: "RuntimeError", message: SENSITIVE_MESSAGE },
              extra: {
                job: "MailInboundProcessJob",
                job_id: "job-123",
                controller: "ExpensesController",
                action: "create",
                safe_status: "retry",
                amount: 1_500_000,
                arguments: [
                  {
                    email: "user@example.com",
                    body_text: "Compra secreta",
                    amount: 1_500_000
                  }
                ],
                params: { description: "Compra secreta" }
              },
              frames: [
                {
                  filename: "app/jobs/mail_inbound_process_job.rb",
                  locals: { password: "hunter2", email: "user@example.com" }
                }
              ]
            }
          },
          custom: {
            payment: {
              amount: 1_500_000,
              credit_limit: 8_000_000,
              interest_rate: 1.8,
              merchant: "Comercio privado",
              category: "Restaurantes",
              card_number: "4111111111111111",
              description: "Compra secreta",
              status: "declined"
            },
            external_response: {
              status: 200,
              message: "Respuesta privada del banco"
            }
          }
        }
      }
    end

    test "removes request bodies, params, cookies, sessions and headers" do
      payload = sanitize(default_payload)
      request = payload[:data][:request]

      assert_equal %i[method request_id url], request.keys.sort
      refute_includes JSON.generate(payload), "Compra secreta"
      refute_includes JSON.generate(payload), "session-token"
      refute_includes JSON.generate(payload), "Bearer secret-token"
    end

    test "drops URL query strings and client IP addresses" do
      payload = sanitize(default_payload)
      request = payload[:data][:request]

      assert_equal "https://app.example.com/expenses", request[:url]
      refute_includes JSON.generate(payload), "203.0.113.10"
      refute_includes JSON.generate(payload), "user%40example.com"
    end

    test "keeps only safe person fields" do
      payload = sanitize(default_payload)
      person = payload[:data][:person]

      assert_equal "3f0c1c0e-6d8d-4a5e-9a7c-1e0f6f3c2a11", person[:id]
      refute person.key?(:email)
      refute person.key?(:username)
    end

    test "removes job arguments and mailer params while keeping the job class" do
      payload = sanitize(default_payload)
      extra = payload[:data][:body][:trace][:extra]

      assert_equal "MailInboundProcessJob", extra[:job]
      assert_equal "job-123", extra[:job_id]
      assert_equal "ExpensesController", extra[:controller]
      assert_equal "retry", extra[:safe_status]
      refute extra.key?(:arguments)
      refute extra.key?(:params)
      refute extra.key?(:amount)
      refute_includes JSON.generate(payload), "body_text"
    end

    test "removes local variables from stack frames" do
      payload = sanitize(default_payload)

      refute payload[:data][:body][:trace][:frames].first.key?(:locals)
      refute_includes JSON.generate(payload), "hunter2"
    end

    test "redacts nested sensitive custom fields" do
      payload = sanitize(default_payload)
      payment = payload[:data][:custom][:payment]

      assert_equal "declined", payment[:status]
      %i[amount credit_limit interest_rate merchant category card_number description].each do |key|
        refute payment.key?(key), "expected #{key} to be removed"
      end
      refute payload[:data][:custom].key?(:external_response)
      refute_includes JSON.generate(payload), "4111111111111111"
      refute_includes JSON.generate(payload), "Comercio privado"
      refute_includes JSON.generate(payload), "Restaurantes"
      refute_includes JSON.generate(payload), "Respuesta privada del banco"
    end

    test "sanitizes exception messages and limits their length" do
      payload = sanitize(default_payload)
      message = payload[:data][:body][:trace][:exception][:message]

      refute_includes message, "user@example.com"
      refute_includes message, "4111"
      refute_includes message, "Bearer"
      refute_includes message, "hunter2"
      refute_includes message, "1500000"
      assert_includes message, "[FILTERED]"
      assert_operator message.length, :<=, RollbarPayloadSanitizer::MAX_MESSAGE_LENGTH
    end

    test "sanitizes trace chains" do
      payload = default_payload
      payload[:data][:body][:trace_chain] = [ payload[:data][:body][:trace].deep_dup ]

      sanitize(payload)

      chain = payload[:data][:body][:trace_chain].first
      refute_includes chain[:exception][:message], "user@example.com"
      refute chain[:extra].key?(:arguments)
      refute chain[:frames].first.key?(:locals)
    end

    test "sanitizes message-only reports" do
      payload = {
        data: {
          body: {
            message: {
              body: "Could not process user@example.com for card 4111 1111 1111 1111",
              extra: { description: "Compra secreta", job: "MailInboundProcessJob" }
            }
          }
        }
      }

      sanitize(payload)

      message = payload[:data][:body][:message]
      refute_includes message[:body], "user@example.com"
      refute_includes message[:body], "4111"
      refute message[:extra].key?(:description)
      assert_equal "MailInboundProcessJob", message[:extra][:job]
    end

    test "sanitizes string context values" do
      payload = { data: { context: "Failed for user@example.com with token=secret-token" } }

      sanitize(payload)

      refute_includes payload[:data][:context], "user@example.com"
      refute_includes payload[:data][:context], "secret-token"
      assert_includes payload[:data][:context], "[FILTERED]"
    end

    test "leaves malformed payloads untouched without raising" do
      assert_nil sanitize(nil)
      assert_equal({}, sanitize({}))

      malformed = { data: "not-a-hash" }
      assert_equal malformed, sanitize(malformed)
    end

    test "preserves safe diagnostic metadata" do
      payload = sanitize(default_payload)

      assert_equal "production", payload[:data][:environment]
      assert_equal "abc123", payload[:data][:code_version]
      assert_equal "POST", payload[:data][:request][:method]
      assert_equal "req-123", payload[:data][:request][:request_id]
      assert_equal "RuntimeError", payload[:data][:body][:trace][:exception][:class]
    end
  end
end
