# frozen_string_literal: true

module Expenses
   class Processor
    class << self
      def call(user:, input:, recording: nil)
        new(user: user, input: input, recording: recording).call
      end
    end

    def initialize(user:, input:, recording: nil)
      @user = user
      @input = input
      @recording = recording
    end

    def call
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      record_input
      unless @input.valid?
        @recording&.add_errors(@input.errors)
        return build_result(nil, nil, started)
      end

      # Every channel starts with the non-applicable markers; the channel
      # processor overwrites the one it implements with real data.
      @recording&.add_step(:ocr, { applicable: false })
      @recording&.add_step(:stt, { applicable: false })

      candidates, engine = processor_for.call

      build_result(candidates, engine, started)
    end

    private

    def record_input
      @recording&.add_step(:input, {
        type: @input.type,
        text: @input.payload[:text],
        image: @input.image? || @input.text_image? ? "(image attached, #{Expenses::Inputs::Image.mime_type(@input.image_data)})" : nil,
        audio: @input.audio? ? "(audio attached, #{Expenses::Inputs::Audio.extension(@input.audio_data, @input.filename)}, #{@input.filename})" : nil
      })
    end

    def processor_for
      case @input.type
      when "audio" then Processors::Audio.new(**processor_attrs)
      when "image", "text_image" then Processors::Image.new(**processor_attrs)
      else Processors::Text.new(**processor_attrs)
      end
    end

    def processor_attrs
      { user: @user, input: @input, recording: @recording }
    end

    def build_result(candidates, engine, started)
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      Result.new(
        candidates: candidates,
        steps: @recording&.steps,
        errors: @recording&.errors,
        warnings: @recording&.warnings,
        duration_ms: duration_ms,
        engine: engine
      )
    end
   end
end
