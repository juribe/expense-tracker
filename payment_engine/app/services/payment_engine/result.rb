# frozen_string_literal: true

module PaymentEngine
  class Result
    attr_accessor :success, :record, :errors, :metadata

    def initialize(success:, record: nil, errors: [], metadata: {})
      @success = success
      @record = record
      @errors = Array(errors)
      @metadata = metadata
    end

    def success?; success; end
    def failure?; !success; end
  end
end
