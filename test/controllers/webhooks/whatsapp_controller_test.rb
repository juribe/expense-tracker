# frozen_string_literal: true

require "test_helper"

# WhatsApp Cloud API webhook entrypoint (GET verify + POST events).
# Mirrors the Meta webhook contract: hub.challenge echo on verify and
# X-Hub-Signature-256 HMAC validation on every POST.
class WhatsappWebhookControllerTest < ActionDispatch::IntegrationTest
  VERIFY_TOKEN = "verify_token_123"
  APP_SECRET = "app_secret_123"

  setup do
    @user = User.create!(
      name: "Whatsapp Webhook User",
      email: "whatsapp_webhook_controller_test@example.com",
      password: "password123"
    )
    @payload = { object: "whatsapp_business_account", entry: [] }.to_json
  end

  test "GET verify echoes hub.challenge with valid token" do
    with_env("WHATSAPP_VERIFY_TOKEN" => VERIFY_TOKEN) do
      get webhooks_whatsapp_path, params: {
        "hub.mode" => "subscribe",
        "hub.verify_token" => VERIFY_TOKEN,
        "hub.challenge" => "challenge_abc"
      }
    end

    assert_response :ok
    assert_equal "challenge_abc", response.body
  end

  test "GET verify fails with wrong token" do
    with_env("WHATSAPP_VERIFY_TOKEN" => VERIFY_TOKEN) do
      get webhooks_whatsapp_path, params: {
        "hub.mode" => "subscribe",
        "hub.verify_token" => "wrong_token",
        "hub.challenge" => "challenge_abc"
      }
    end

    assert_response :forbidden
  end

  test "POST webhook returns 401 without signature header" do
    with_env("FB_APP_SECRET" => APP_SECRET) do
      post webhooks_whatsapp_path, params: @payload, headers: { "Content-Type" => "application/json" }
    end

    assert_response :unauthorized
  end

  test "POST webhook returns 401 with tampered signature" do
    with_env("FB_APP_SECRET" => APP_SECRET) do
      post webhooks_whatsapp_path, params: @payload, headers: {
        "Content-Type" => "application/json",
        "X-Hub-Signature-256" => "sha256=" + ("a" * 64)
      }
    end

    assert_response :unauthorized
  end

  test "POST webhook with valid signature enqueues the raw body and returns 200" do
    with_env("FB_APP_SECRET" => APP_SECRET, "WHATSAPP_VERIFY_TOKEN" => VERIFY_TOKEN) do
      signature = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", APP_SECRET, @payload)

      with_active_job_adapter(:test) do
        assert_enqueued_with(job: WhatsappWebhookJob, args: [@payload]) do
          post webhooks_whatsapp_path, params: @payload, headers: {
            "Content-Type" => "application/json",
            "X-Hub-Signature-256" => signature
          }
        end
      end
    end

    assert_response :ok
  end
end
