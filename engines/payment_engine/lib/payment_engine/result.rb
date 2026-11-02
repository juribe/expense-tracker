module PaymentEngine
  # Structured return value used by every public service and provider adapter.
  # Commercial validation failures are returned as errors, not raised.
  class Result
    attr_reader :data, :errors, :code

    def initialize(success:, data: nil, errors: [], code: nil)
      @success = success
      @data = data
      @errors = Array(errors).compact
      @code = code
    end

    def self.success(data: nil, code: nil)
      new(success: true, data: data, code: code)
    end

    def self.failure(errors: [], code: nil, data: nil)
      new(success: false, data: data, errors: Array(errors).presence || [ "Operation failed" ], code: code)
    end

    def success?
      @success
    end

    def error?
      !success?
    end
    alias failure? error?

    def error_message
      errors.join(", ")
    end

    def [](key)
      return unless data.respond_to?(:[])

      data[key]
    end

    def to_h
      { success: success?, data: data, errors: errors, code: code }
    end
  end
end
