# frozen_string_literal: true

module Ai
  # Optional execution overrides threaded through the existing ingestion
  # pipeline. Production calls use no override; an evaluation run carries the
  # provider/model it is measuring and forces the AI path so the model is
  # exercised on every dataset row (the deterministic and cache short-circuits
  # are skipped).
  #
  #   Ai::Execution.new(provider: "openrouter", model: "upstage/solar-pro4", force_ai: true)
  class Execution
    attr_reader :provider, :model

    def initialize(provider: nil, model: nil, force_ai: false)
      @provider = provider
      @model = model
      @force_ai = force_ai
    end

    def override?
      @provider.present? && @model.present?
    end

    def force_ai?
      @force_ai || override?
    end
  end
end