# frozen_string_literal: true

require "test_helper"

class FinancialAnalysisServiceTest < ActionCable::TestCase
  STREAM = "financial_chat_user_%{user_id}"

  setup do
    @user = User.create!(
      name: "Test User",
      email: "financial_analysis_test@example.com",
      password: "password123"
    )
    @chat = FinancialChat.for_user(@user)
    @question = @chat.messages.create!(role: "user", content: "¿Cuánto gasté este mes?", status: "sent")
    @fake = FakeAiProvider.new(responses: [])
  end

  def run_service(broadcast_interval: 0.0)
    fake = @fake
    stub_method(Ai::Providers, :strong, ->(**_kwargs) { fake }) do
      FinancialAnalysisService.new(
        chat_id: @chat.id, message_id: @question.id, broadcast_interval: broadcast_interval
      ).call
    end
  end

  def user_stream
    FinancialChatChannel.stream_name_for(@user)
  end

  def events_on_stream
    transmissions.map { |p| p["event"] }
  end

  test "broadcasts processing, deltas and completion, and persists the assistant answer" do
    @fake.responses << { content: "Gastaste **COP 17.800.000** este mes.", output_tokens: 42, input_tokens: 100 }

    run_service

    events = events_on_stream
    assert_equal %w[assistant_processing assistant_delta assistant_completed], events.uniq

    answer = @chat.messages.reload.where(role: "assistant").sole
    assert_equal "Gastaste **COP 17.800.000** este mes.", answer.content
    assert_equal "complete", answer.status
    assert_equal "fake-model", answer.model
    assert_equal 42, answer.output_tokens
  end

  test "completed event carries the rendered HTML answer" do
    @fake.responses << { content: "Gastaste **COP 17.800.000**" }

    run_service

    payload = transmissions.find { |p| p["event"] == "assistant_completed" }
    assert_includes payload.dig("message", "content"), "<strong>COP 17.800.000</strong>"
    assert_equal "assistant", payload.dig("message", "role")
  end

  test "delta events carry incremental text" do
    @fake.responses << { content: "Primera parte. Segunda parte." }

    run_service

    deltas = transmissions.select { |p| p["event"] == "assistant_delta" }
                          .map { |p| p["delta"] }
    assert_equal "Primera parte. Segunda parte.", deltas.join
  end

  test "sends the system prompt with financial context, history and the question" do
    @fake.responses << { content: "ok" }
    prior_answer = @chat.messages.create!(role: "assistant", content: "Respuesta previa", status: "complete")
    prior_answer.update_column(:created_at, 1.minute.ago) # rubocop:disable Rails/SkipsModelValidations
    @question.update_column(:created_at, 30.seconds.ago) # rubocop:disable Rails/SkipsModelValidations

    run_service

    messages = @fake.calls.sole
    assert_equal "system", messages.first[:role]
    system_prompt = messages.first[:content]
    assert_match(/analista financiero/i, system_prompt)
    assert_match(/COP/, system_prompt)

    history = messages[1..]
    assert_equal "Respuesta previa", history.first[:content]
    assert_equal "¿Cuánto gasté este mes?", history.last[:content]
  end

  test "includes expense, income and budget data in the system prompt" do
    @fake.responses << { content: "ok" }
    category = Category.create!(name: "Restaurantes", is_default: true, category_type: "expense")
    @user.expenses.create!(amount: 85_000, date: Date.today, category: category, description: "Almuerzo")
    @user.incomes.create!(amount: 4_500_000, date: Date.today, category: category, description: "Salario")
    @user.budgets.create!(category: category, monthly_amount: 500_000)

    run_service

    system_prompt = @fake.calls.sole.first[:content]
    assert_match(/Restaurantes/, system_prompt)
    assert_match(/85\.000/, system_prompt)
    assert_match(/4\.500\.000/, system_prompt)
    assert_match(/500\.000/, system_prompt)
  end

  test "provider failure broadcasts assistant_failed and persists nothing" do
    @fake.responses << Ai::Provider::Error.new("LLM timeout")

    run_service

    events = events_on_stream
    assert_includes events, "assistant_failed"
    assert_not_includes events, "assistant_completed"
    assert_equal 0, @chat.messages.reload.where(role: "assistant").count
  end

  test "provider failure records the error in AiRequest" do
    @fake.responses << Ai::Provider::Error.new("LLM timeout")

    run_service

    request = AiRequest.order(:created_at).last
    assert_equal "financial_chat", request.task
    assert_equal "strong_ai", request.strategy
    assert_equal "error", request.status
    assert_match(/LLM timeout/, request.error)
  end

  test "success records the strong_ai usage in AiRequest" do
    @fake.responses << { content: "ok", output_tokens: 30, input_tokens: 100 }

    run_service

    request = AiRequest.order(:created_at).last
    assert_equal "ok", request.status
    assert_equal 30, request.output_tokens
    assert request.latency_ms.present?
  end

  test "missing message or assistant message is a no-op" do
    assert_nothing_raised do
      FinancialAnalysisService.new(chat_id: @chat.id, message_id: 999_999).call
    end
  end

  test "strong tier disabled flag does not block the chat" do
    @fake.responses << { content: "ok", output_tokens: 5, input_tokens: 10 }

    with_env({ "AI_DISABLE_STRONG_TIER" => "true" }) do
      run_service
    end

    assert_includes events_on_stream, "assistant_completed"
    assert_equal 1, @chat.messages.reload.where(role: "assistant").count
    assert_equal "strong_ai", AiRequest.order(:created_at).last.strategy
  end

  test "unconfigured provider broadcasts assistant_failed" do
    stub_method(Ai::Providers, :strong, ->(**_kwargs) { nil }) do
      FinancialAnalysisService.new(chat_id: @chat.id, message_id: @question.id).call
    end

    assert_includes events_on_stream, "assistant_failed"
    assert_equal 0, @chat.messages.reload.where(role: "assistant").count
  end

  private

  def payloads
    broadcasts(user_stream).map { |message| message.is_a?(String) ? JSON.parse(message) : message }
  end

  def transmissions
    payloads.select { |p| p["user_message_id"] == @question.id }
  end

  def events_on_stream
    transmissions.map { |p| p["event"] }
  end
end
