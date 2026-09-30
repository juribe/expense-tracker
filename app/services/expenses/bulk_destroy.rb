# frozen_string_literal: true

module Expenses
  # Destroys many expenses of one user in bulk, tallying per-record failures.
  #
  #   result = Expenses::BulkDestroy.call(user: user, ids: ["1", 2, "3,4"])
  #   result.success?       # false when there is nothing to destroy
  #   result.deleted_count  # records actually destroyed
  #   result.failed_count   # records that refused destruction
  class BulkDestroy
    def self.call(user:, ids:)
      new(user: user, ids: ids).call
    end

    attr_reader :deleted_count, :failed_count, :error_key

    def initialize(user:, ids:)
      @user = user
      @ids = ids
      @deleted_count = 0
      @failed_count = 0
      @error_key = nil
    end

    def call
      scope = user.expenses.where(id: parse_ids)
      count = scope.count

      if count.zero?
        @error_key = :no_selection
        return self
      end

      scope.find_each do |expense|
        begin
          expense.destroy!
          @deleted_count += 1
        rescue ActiveRecord::RecordNotDestroyed
          @failed_count += 1
        end
      end

      self
    end

    def success?
      error_key.nil?
    end

    def failure?
      !success?
    end

    private

    attr_reader :user, :raw_ids

    def raw_ids
      @ids
    end

    def parse_ids
      Array(@ids).flat_map { |value| value.to_s.split(",") }.map(&:to_i).reject(&:zero?)
    end
  end
end
