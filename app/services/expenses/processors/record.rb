module Expenses
  module Processors
    # Record a new expense in the database. This is the last step of the
    # processing pipeline, after all the other processors have extracted and
    # validated the data.
    class Recording
      attr_accessor :execution, :steps, :errors, :warnings

      def initialize(execution:, steps: {}, errors: [], warnings: [])
        @execution = execution
        @steps = steps
        @errors = errors
        @warnings = warnings
      end

      # def call
      #   return unless @execution

      #   @execution.update!(
      #     status: :recorded,
      #     recorded_at: Time.current,
      #     steps: @steps,
      #     errors: @errors,
      #     warnings: @warnings
      #   )
      # end
    end
  end
end