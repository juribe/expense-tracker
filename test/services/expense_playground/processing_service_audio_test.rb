# frozen_string_literal: true

require "test_helper"

module ExpensePlayground
  # Audio inputs are just another way of producing text: the transcript flows
  # through the SAME ExpenseParser → normalization → validation pipeline used
  # for typed text. SpeechToText is stubbed — no Whisper execution here.
  class ProcessingServiceAudioTest < ActiveSupport::TestCase
    AUDIO_DATA = "data:audio/ogg;base64,#{Base64.strict_encode64('OGGDATABYTES')}"

    setup do
      @user = User.create!(name: "Audio Playground User", email: "playground-audio@example.com", password: "password123")
      @restaurants = Category.create!(name: "Restaurants", is_default: true, category_type: "expense")
      @saved_api_key = ENV.delete("MISTRAL_API_KEY")
    end

    teardown do
      ENV["MISTRAL_API_KEY"] = @saved_api_key
    end

    def stub_transcription(**attrs)
      result = SpeechToText::Result.new(
        text: attrs[:text] || "Me gasté 50 mil en almuerzos",
        language: attrs[:language] || "es",
        language_probability: attrs[:language_probability] || 0.97,
        duration: attrs[:duration] || 5.2,
        provider: attrs[:provider] || "whisper",
        model: attrs[:model] || "small"
      )
      stub_method(SpeechToText, :transcribe, result) { yield }
    end

    def process(input)
      ProcessingService.call(user: @user, input: input)
    end

    test "audio input is transcribed and extracted through the normal text pipeline" do
      assert_no_difference -> { Expense.count } do
        stub_transcription do
          result = process(Input.new(type: :audio, audio_data: AUDIO_DATA,
                                     metadata: { filename: "note.ogg" }))

          assert result.ok?
          assert_equal "heuristic", result.engine

          candidate = result.candidate
          assert_equal BigDecimal(50_000.to_s), candidate.amount
          assert_equal "COP", candidate.currency
          assert_equal @restaurants.id, candidate.category_id
          assert_equal Date.current, candidate.date
          assert candidate.confidence.present?
        end
      end
    end

    test "the transcript and provider metadata are recorded in the stt step" do
      stub_transcription do
        result = process(Input.new(type: :audio, audio_data: AUDIO_DATA, metadata: { filename: "note.ogg" }))

        stt = result.steps[:stt]
        assert stt[:applicable]
        assert_equal "whisper", stt[:provider]
        assert_equal "small", stt[:model]
        assert_equal "es", stt[:language]
        assert_equal 0.97, stt[:language_probability]
        assert_equal 5.2, stt[:duration]
        assert_match(/50 mil/, stt[:text])

        assert_equal false, result.steps[:ocr][:applicable]
      end
    end

    test "audio processing never creates a real expense" do
      stub_transcription do
        assert_no_difference -> { Expense.count } do
          result = process(Input.new(type: :audio, audio_data: AUDIO_DATA))
          assert result.ok?
        end
      end
    end

    test "an empty transcript surfaces a friendly error and no candidate" do
      stub_transcription(text: "") do
        result = process(Input.new(type: :audio, audio_data: AUDIO_DATA))

        assert_not result.ok?
        assert_nil result.candidate
        assert result.errors.any? { |error| error.include?("empty transcript") }
      end
    end

    test "speech-to-text failures become pipeline errors, not crashes" do
      stub_method(SpeechToText, :transcribe,
        ->(**_kwargs) { raise SpeechToText::TranscriptionError, "Speech-to-text failed. Whisper could not transcribe this audio." }) do
        result = process(Input.new(type: :audio, audio_data: AUDIO_DATA))

        assert_not result.ok?
        assert_nil result.candidate
        assert result.errors.any? { |error| error.include?("Whisper could not transcribe") }
        assert_equal "whisper", result.steps[:stt][:provider]
        assert result.steps[:stt][:error].present?
      end
    end

    test "unsupported audio input is rejected before speech-to-text runs" do
      result = process(Input.new(type: :audio, audio_data: "data:video/mp4;base64,AAAA", metadata: { filename: "clip.mp4" }))

      assert_not result.ok?
      assert_nil result.candidate
      assert result.errors.any? { |error| error.include?("Unsupported audio format") }
    end

    test "non-audio inputs keep the speech-to-text step marked as not applicable" do
      result = process(Input.new(type: :text, text: "Me gasté 50mil en almuerzos"))

      assert result.ok?
      assert_equal false, result.steps[:stt][:applicable]
    end
  end
end
