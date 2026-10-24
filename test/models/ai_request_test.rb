# frozen_string_literal: true

require "test_helper"

# AiRequest telemetría contiene conversaciones financieras: prompt/salidas
# esperan cifradas en reposo con la misma clave de EncryptedSecret que los
# OAuth tokens; el prompt mantiene su representación de array de mensajes.
class AiRequestTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "AI Request User", email: "ai_request@example.com", password: "password123")
  end

  test "prompt and output are stored encrypted at rest" do
    record = AiRequest.create!(user: @user, task: "expense_extraction", strategy: "cheap_ai", status: "ok",
                               prompt: [ { role: "user", content: "gasto de 50000 en transporte" } ],
                               output: "El gasto se registró en transporte")

    raw_prompt = record.read_attribute(:prompt)
    raw_output = record.read_attribute(:output)

    assert_not_includes raw_prompt, "gasto de 50000"
    assert_not_includes raw_output, "El gasto se registró"
  end

  test "prompt roundtrips as the message array" do
    record = AiRequest.create!(user: @user, task: "expense_extraction", strategy: "cache", status: "ok",
                               prompt: [ { role: "user", content: "gasto 40000 uber" },
                                         { role: "assistant", content: "clasificado como transporte" } ],
                               output: "ok")

    # jsonb typing stringifies keys, so the roundtrip keeps string keys.
    assert_equal [ { "role" => "user", "content" => "gasto 40000 uber" },
                   { "role" => "assistant", "content" => "clasificado como transporte" } ],
                 AiRequest.find(record.id).prompt
  end

  test "blank prompts stay blank" do
    record = AiRequest.create!(user: @user, task: "expense_extraction", strategy: "cache", status: "ok")

    assert_nil record.prompt
    assert_nil record.output
  end
end
