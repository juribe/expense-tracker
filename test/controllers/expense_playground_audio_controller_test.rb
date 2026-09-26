# frozen_string_literal: true

require "test_helper"

# End-to-end Playground flow for audio inputs, with SpeechToText stubbed so
# tests never execute Whisper. The run endpoint must produce a transcript +
# ExpenseCandidate WITHOUT creating an expense; persistence happens only
# through the explicit +create+ endpoint.
class ExpensePlaygroundAudioControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  AUDIO_DATA = "data:audio/ogg;base64,#{Base64.strict_encode64('OGGDATABYTES')}"

  setup do
    @user = User.create!(name: "Audio Playground Controller User", email: "pg-audio@example.com", password: "password123")
    @restaurants = Category.create!(name: "Restaurants", is_default: true, category_type: "expense")
    sign_in @user
    @saved_api_key = ENV.delete("MISTRAL_API_KEY")
  end

  teardown do
    ENV["MISTRAL_API_KEY"] = @saved_api_key
  end

  test "uploading audio shows the audio tab and player on the playground page" do
    get expense_playground_path
    assert_response :success
    assert_match "data-pg-tab=\"audio\"", response.body
    assert_match "pgAudioInput", response.body
    assert_match "pgAudioPreview", response.body
  end

  test "audio processing displays the transcript and candidate without creating an expense" do
    transcript = SpeechToText::Result.new(text: "Me gasté 50 mil en almuerzos", language: "es",
                                          language_probability: 0.97, duration: 5.2,
                                          provider: "whisper", model: "small")

    assert_no_difference -> { Expense.count } do
      assert_no_difference -> { Category.count } do
        stub_method(SpeechToText, :transcribe, transcript) do
          stub_ai_extraction(
            parsed_expense(original_text: "Me gasté 50 mil en almuerzos", amount: 50_000, description: "almuerzos")
          ) do
            post expense_playground_process_path(format: :json), params: {
              type: "audio", audio_data: AUDIO_DATA, filename: "note.ogg", input_label: "note.ogg"
            }
          end
        end
      end
    end

    assert_response :success
    data = JSON.parse(response.body)

    assert data["ok"]
    stt = data["steps"]["stt"]
    assert_equal "whisper", stt["provider"]
    assert_equal "small", stt["model"]
    assert_equal "es", stt["language"]
    assert_equal "Me gasté 50 mil en almuerzos", stt["text"]

    candidate = data["candidate"]
    assert_equal 50_000.0, candidate["amount"].to_f
    assert_equal @restaurants.id, candidate["category_id"]
    assert_equal "playground", candidate["source"]

    run = @user.expense_playground_runs.recent_first.first
    assert_equal "audio", run.input_type
    assert_equal "note.ogg", run.input_label
    assert_nil run.expense_id
  end

  test "the created expense is still an explicit second step after processing audio" do
    transcript = SpeechToText::Result.new(text: "Me gasté 50 mil en almuerzos", language: "es",
                                          provider: "whisper", model: "small")

    stub_method(SpeechToText, :transcribe, transcript) do
      stub_ai_extraction(
        parsed_expense(original_text: "Me gasté 50 mil en almuerzos", amount: 50_000, description: "almuerzos")
      ) do
        post expense_playground_process_path(format: :json),
             params: { type: "audio", audio_data: AUDIO_DATA, filename: "note.ogg", input_label: "note.ogg" }
      end
    end
    assert_response :success
    run_id = JSON.parse(response.body)["run_id"]

    assert_no_difference -> { Expense.count } do
      stub_ai_extraction(
        parsed_expense(original_text: "Me gasté 50 mil en almuerzos", amount: 50_000, description: "almuerzos")
      ) do
        post expense_playground_process_path(format: :json),
             params: { type: "audio", audio_data: AUDIO_DATA, filename: "note.ogg" }
      end
    end

    assert_difference -> { Expense.count }, 1 do
      post expense_playground_create_path(format: :json), params: {
        run_id: run_id,
        candidate: {
          amount: "50000",
          currency: "COP",
          category_id: @restaurants.id,
          description: "almuerzos",
          date: Date.current.iso8601,
          source: "playground"
        }
      }
    end
    assert_response :created
  end

  test "unsupported audio formats are rejected with a friendly error" do
    post expense_playground_process_path(format: :json),
         params: { type: "audio", audio_data: "data:video/mp4;base64,AAAA", filename: "clip.mp4" }

    assert_response :unprocessable_entity
    errors = JSON.parse(response.body)["errors"]
    assert errors.any? { |error| error.include?("Unsupported audio format") }
  end

  private

  def parsed_expense(original_text:, amount:, description:, date: Date.current, category: "Restaurants",
                     confidence: 0.9, money_source_hint: nil)
    Ai::Tasks::ParsedExpense.new(
      original_text: original_text,
      amount: amount,
      date: date.iso8601,
      description: description,
      category: category,
      money_source_hint: money_source_hint,
      confidence: confidence
    )
  end

  def stub_ai_extraction(*expenses)
    router_result = Ai::Router::Result.new(
      ok?: true,
      data: expenses,
      confidence: expenses.map(&:confidence).compact.max || 0.9,
      strategy: "cheap_ai",
      error: nil
    )
    stub_method(Ai::Router, :call, ->(**_kwargs) { router_result }) { yield }
  end
end
