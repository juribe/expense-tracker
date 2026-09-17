# frozen_string_literal: true

module ExpenseProcessing
  # The expense processor: orchestrates the full ingestion pipeline for any
  # normalized input, shared by every entry point (playground, WhatsApp/email/
  # voice channels, an API, ...).
  #
  #   input -> (route) channel processor -> ExpenseCandidate
  #
  # It routes to the matching channel processor (Text / Image / Audio), which
  # composes the shared Text core when the channel merely produces text
  # (speech-to-text, OCR). It ONLY records the :input step, the non-applicable
  # ocr/stt steps and the timing; everything else is the processors' job.
  #
  # It NEVER persists anything. Every entry point receives a Result with the
  # candidate plus every pipeline stage recorded for debugging.
  #
  #   result = ExpenseProcessing::Processor.call(user: user, input: input)
  #   result.ok?             # => true
  #   result.candidate       # => ExpenseCandidate
  #   result.steps[:stt]     # => { applicable: false } | { provider: ..., text: ... }
  #   result.steps[:ocr]     # => { applicable: false } | { applicable: true, text: ..., engine: ... }
  class Processor
    class << self
      def call(user:, input:, execution: nil)
        new(user: user, input: input, execution: execution).call
      end
    end

    def initialize(user:, input:, execution: nil)
      @user = user
      @input = input
      @execution = execution
      @steps = {}
      @errors = []
      @warnings = []
    end

    def call
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      record_input
      unless @input.valid?
        @errors.concat(@input.errors)
        return build_result(nil, nil, started)
      end

      # Every channel starts with the non-applicable markers; the channel
      # processor overwrites the one it implements with real data.
      @steps[:ocr] = { applicable: false }
      @steps[:stt] = { applicable: false }

      candidate, engine = processor_for.call

      build_result(candidate, engine, started)
    end

    private

    def record_input
      @steps[:input] = {
        type: @input.type,
        text: @input.payload[:text],
        image: @input.image? || @input.text_image? ? "(image attached, #{ExpensePlayground::Inputs::Image.mime_type(@input.image_data)})" : nil,
        audio: @input.audio? ? "(audio attached, #{ExpensePlayground::Inputs::Audio.extension(@input.audio_data, @input.filename)}, #{@input.filename})" : nil
      }
    end

    def processor_for
      case @input.type
      when "audio" then Processors::Audio.new(**processor_attrs)
      when "image", "text_image" then Processors::Image.new(**processor_attrs)
      else Processors::Text.new(**processor_attrs)
      end
    end

    def processor_attrs
      { user: @user, input: @input, execution: @execution, steps: @steps, errors: @errors, warnings: @warnings }
    end

    def build_result(candidate, engine, started)
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      Result.new(
        candidate: candidate,
        steps: @steps,
        errors: @errors.dup,
        warnings: @warnings.dup,
        duration_ms: duration_ms,
        engine: engine
      )
    end
  end
end
