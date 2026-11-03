module PaymentEngine
  class Result
    attr_reader :data, :record, :errors, :code, :metadata, :success

    def initialize(success:, data: nil, record: nil, errors: [], code: nil, metadata: {})
      @success = success
      @data = data || record
      @record = record || data
      @errors = Array(errors).compact
      @code = code
      @metadata = metadata
    end

    def self.success(data: nil, record: nil, code: nil, metadata: {})
      new(success: true, data: data || record, record: record || data, code: code, metadata: metadata)
    end

    def self.failure(errors: [], code: nil, data: nil, record: nil, metadata: {})
      new(success: false, data: data || record, record: record || data, errors: Array(errors).presence || ["Operation failed"], code: code, metadata: metadata)
    end

    def success?
      @success == true
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
      { success: success?, data: data, errors: errors, code: code, metadata: metadata }
    end
  end
end