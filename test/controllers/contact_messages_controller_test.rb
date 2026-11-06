# frozen_string_literal: true

require "test_helper"

# Public contact endpoint used by the Maglev Contáctanos page. It must remain
# usable without authentication and never trust client-side validation.
class ContactMessagesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  VALID_MESSAGE = {
    contact_message: {
      name: "Ana Pérez",
      email: "ana@example.com",
      subject: "Necesito soporte",
      message: "No puedo registrar un gasto."
    }
  }.freeze

  test "un envío válido encola un correo y responde éxito" do
    with_active_job_adapter(:test) do
      assert_enqueued_email_with ContactMailer, :new_message, params: {
        name: "Ana Pérez",
        email: "ana@example.com",
        subject: "Necesito soporte",
        message: "No puedo registrar un gasto."
      } do
        post "/contact", params: VALID_MESSAGE, as: :json
      end
    end

    assert_response :success
    data = JSON.parse(response.body)
    assert_equal true, data["ok"]
    refute_includes response.body, "hola@yogasto.co"
  end

  test "un mensaje inválido responde 422 y no envía correo" do
    with_active_job_adapter(:test) do
      assert_no_enqueued_emails do
        post "/contact", params: {
          contact_message: {
            name: "",
            email: "no-es-un-correo",
            subject: "",
            message: ""
          }
        }, as: :json
      end
    end

    assert_response :unprocessable_entity
    data = JSON.parse(response.body)
    assert_equal false, data["ok"]
    assert data["errors"].key?("name")
    assert data["errors"].key?("email")
    assert data["errors"].key?("subject")
    assert data["errors"].key?("message")
  end

  test "el honeypot bloquea el envío sin revelarlo" do
    with_active_job_adapter(:test) do
      assert_no_enqueued_emails do
        post "/contact", params: {
          contact_message: VALID_MESSAGE[:contact_message].merge(website: "https://spam.example")
        }, as: :json
      end
    end

    assert_response :success
    assert_equal true, JSON.parse(response.body)["ok"]
  end

  test "evita duplicados accidentales en una ventana corta" do
    with_memory_cache do
      with_active_job_adapter(:test) do
        assert_enqueued_emails 1 do
          2.times { post "/contact", params: VALID_MESSAGE, as: :json }
        end
      end
    end

    assert_response :success
  end

  test "aplica rate limiting por IP" do
    with_memory_cache do
      with_active_job_adapter(:test) do
        assert_enqueued_emails 5 do
          5.times do |index|
            post "/contact", params: {
              contact_message: VALID_MESSAGE[:contact_message].merge(
                message: "Mensaje número #{index}"
              )
            }, as: :json
          end

          post "/contact", params: {
            contact_message: VALID_MESSAGE[:contact_message].merge(message: "Mensaje bloqueado")
          }, as: :json
        end
      end
    end

    assert_response :too_many_requests
    data = JSON.parse(response.body)
    assert_equal false, data["ok"]
    assert data["error"].present?
  end

  test "el envío HTML exitoso redirige con confirmación" do
    with_active_job_adapter(:test) do
      assert_enqueued_emails 1 do
        post "/contact", params: VALID_MESSAGE
      end
    end

    assert_redirected_to "/contact?sent=1"
  end

  test "el envío HTML inválido redirige con error" do
    with_active_job_adapter(:test) do
      assert_no_enqueued_emails do
        post "/contact", params: {
          contact_message: { name: "", email: "no-es-un-correo", subject: "", message: "" }
        }
      end
    end

    assert_redirected_to "/contact?error=1"
  end

  test "un payload malformado responde 422 sin enviar correo" do
    with_active_job_adapter(:test) do
      assert_no_enqueued_emails do
        post "/contact", params: { contact_message: "no-es-un-objeto" }, as: :json
      end
    end

    assert_response :unprocessable_entity
    data = JSON.parse(response.body)
    assert_equal false, data["ok"]
    assert data["errors"].key?("name")
  end

  test "el formulario es público para visitantes no autenticados" do
    with_active_job_adapter(:test) do
      post "/contact", params: VALID_MESSAGE, as: :json
    end

    assert_response :success
  end

  private

  def with_memory_cache
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = original_cache
  end
end
