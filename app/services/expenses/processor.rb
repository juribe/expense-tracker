# frozen_string_literal: true

module Expenses
   class Processor
    class << self
      def call(user:, input:, recording: nil, execution: nil, source: nil)
        new(user: user, input: input, recording: recording, execution: execution, source: source).call
      end
    end

    def initialize(user:, input:, recording: nil, execution: nil, source: nil)
      @user = user
      @input = input
      @recording = recording || Expenses::Processors::Recording.new(execution: execution)
      @source = source
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
      candidates = Array(candidates).map { |c| persist_candidate(c, engine: engine) }

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

    def persist_candidate(candidate, engine:)
      return candidate if candidate.is_a?(ExpenseCandidate) && candidate.persisted?

      persisted = ExpenseCandidate.create!(
        user: @user,
        amount: candidate.amount,
        date: candidate.date,
        description: candidate.description.presence || candidate.merchant,
        category_id: candidate.category_id,
        money_source_id: candidate.money_source_id,
        source: @source || @input.type || "text",
        confidence: candidate.confidence,
        original_input: @input.payload[:text],
        original_text: candidate.respond_to?(:original_text) ? candidate.original_text : nil,
        category_suggestion: candidate.respond_to?(:suggested_category_name) ? candidate.suggested_category_name : nil,
        metadata: {
          engine: engine,
          classification_source: candidate.classification_source,
          category_name: candidate.category_name,
          money_source_name: candidate.money_source_name,
          warnings: candidate.warnings
        }.compact
      )
      # Copy transient attributes for pipeline consumers.
      persisted.currency = candidate.currency if candidate.respond_to?(:currency)
      persisted.merchant = candidate.merchant if candidate.respond_to?(:merchant)
      persisted.category_name = candidate.category_name if candidate.respond_to?(:category_name)
      persisted.money_source_name = candidate.money_source_name if candidate.respond_to?(:money_source_name)
      persisted.classification_source = candidate.classification_source if candidate.respond_to?(:classification_source)
      persisted.suggested_category_name = candidate.suggested_category_name if candidate.respond_to?(:suggested_category_name)
      persisted.warnings = candidate.warnings if candidate.respond_to?(:warnings)
      persisted
    rescue ActiveRecord::RecordInvalid
      candidate
    end
   end
end
