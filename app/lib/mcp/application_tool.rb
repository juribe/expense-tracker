# frozen_string_literal: true

module Mcp
  # ApplicationTool
  # Base class for every MCP tool. Provides the authenticated user, scope
  # checks, the uniform JSON success/error envelope and the write audit trail.
  #
  # Example: class GetThingTool < Mcp::ApplicationTool
  #            requires_scope :read
  #            def call
  #              success(things: [])
  #            end
  #          end
  class ApplicationTool < ::FastMcp::Tool
    include Mcp::ToolArguments

    class << self
      def requires_scope(scope)
        @required_scope = scope.to_s
      end

      def required_scope
        @required_scope
      end
    end

    def call_with_schema_validation!(**args)
      payload = execute(**args)
      record_audit(args) if self.class.required_scope == "write"
      [ payload, _meta ]
    end

    private

    def execute(**args)
      validation = self.class.input_schema.call(args)
      if validation.errors.any?
        return error_response("INVALID_ARGUMENT", validation_errors(validation.errors.to_h))
      end

      call(**args)
    rescue Mcp::Error => e
      error_response(e.code, e.message)
    rescue ActiveRecord::RecordNotFound
      error_response("NOT_FOUND", "The requested record was not found.")
    rescue ActiveRecord::RecordInvalid => e
      error_response("INVALID_ARGUMENT", e.record.errors.full_messages.to_sentence)
    rescue StandardError => e
      Rails.logger.error("[mcp] #{self.class.tool_name} failed: #{e.class}")
      error_response("INTERNAL_ERROR", "The operation could not be completed.")
    end

    def record_audit(args)
      user = Mcp::Current.user
      return if user.nil?

      Mcp::Audit.record(
        user: user,
        token: Mcp::Current.token,
        tool_name: self.class.tool_name,
        status: @last_error ? "failed" : "succeeded",
        error_code: @last_error && @last_error[:code],
        resource_id: resource_id,
        argument_keys: args.keys
      )
    end

    def resource_id
      return nil unless @last_payload.is_a?(Hash)

      @last_payload[:id] || @last_payload["id"]
    end

    def user
      Mcp::Current.user || raise(Mcp::Error.new("UNAUTHENTICATED", "No authenticated user."))
    end

    def success(data)
      @last_payload = data
      result(success: true, data: data)
    end

    def failure(code, message)
      error_response(code, message)
    end

    def result(payload)
      { content: [ { type: "text", text: JSON.generate(payload) } ] }
    end

    def error_response(code, message)
      @last_error = { code: code, message: message }
      {
        content: [ {
          type: "text",
          text: JSON.generate(success: false, error: { code: code, message: message })
        } ],
        isError: true
      }
    end

    def validation_errors(errors)
      errors.map { |field, messages| "#{field}: #{Array(messages).join(', ')}" }.join("; ")
    end
  end
end
