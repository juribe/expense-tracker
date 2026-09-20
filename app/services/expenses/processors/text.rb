# frozen_string_literal: true

module Expenses
  module Processors
    class Text < Base
      def call(text = nil, context: nil)
        result = ExpenseResolver::Service.call(text: text || note, user: @user, context: context, recording: @recording)
        if result.failure?
          log_error(result.errors)
          return [ nil, "IA" ]
        end

        candidates = result.result
        validate_all(candidates)
        [ candidates, "IA" ]
      end

      def log_error(errors)
        Rails.logger.error("ExpenseResolver::Service failed with errors: #{errors.inspect}")
        @recording&.add_errors(errors)
      end

      def validate_all(candidates)
        return unless @recording

        @recording.steps[:validation] = []
        candidates.each { |candidate| validate(candidate) }
      end

      def validate(candidate)
        return unless @recording

        @recording.steps[:validation] ||= []
        @recording.steps[:validation] << {
          candidate: candidate,
          valid: candidate.valid?,
          checks: candidate.checks,
          errors: candidate.errors
        }
      end
    end
  end
end
