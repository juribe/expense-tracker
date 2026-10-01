# frozen_string_literal: true

require "test_helper"

class SvcDebug2Test < ActionCable::TestCase
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(name: "D2", email: "svc_debug2@example.com", password: "password123")
    @chat = FinancialChat.for_user(@user)
    @question = @chat.messages.create!(role: "user", content: "gaste?", status: "sent")
    @fake = FakeAiProvider.new(responses: [])
  end

  test "run_service clone" do
    @fake.responses << { content: "Gastaste **COP 17.800.000** este mes.", output_tokens: 42, input_tokens: 100 }

    stub_method(Ai::Providers, :strong, ->(**_kwargs) { @fake }) do
      FinancialAnalysisService.new(
        chat_id: @chat.id, message_id: @question.id, broadcast_interval: 0.0
      ).call
    end

    puts "ASSISTANT=#{@chat.messages.reload.where(role: :assistant).count}"
    puts "STRONG_CLASS_IN_LAMBDA_CHECK"
  end
end
