# frozen_string_literal: true

module Goals
  # Marks a satisfied goal as archived without touching its allocation
  # history. The saved amount remains derived from the same records.
  class Complete
    Result = Struct.new(:success, :error, keyword_init: true) do
      def success?
        success
      end
    end

    def self.call(goal:)
      new(goal: goal).call
    end

    def initialize(goal:)
      @goal = goal
    end

    def call
      return Result.new(success: false, error: :target_not_reached) unless @goal.completed?
      return Result.new(success: true) if @goal.archived?

      @goal.update!(status: "archived")
      Result.new(success: true)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success: false, error: e.record.errors.full_messages.first)
    end
  end
end
