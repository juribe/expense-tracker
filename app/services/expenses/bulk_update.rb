# frozen_string_literal: true

module Expenses
  # Updates category and/or money source of many expenses of one user in a
  # single statement, after validating ownership of both referenced records.
  #
  #   result = Expenses::BulkUpdate.call(
  #     user: user, ids: [1, "2,3"], category_id: 7, money_source_id: nil
  #   )
  #   result.success?       # false on :no_selection / :nothing_to_change /
  #                         # :category_not_found / :source_not_found
  #   result.updated_count  # number of rows updated
  class BulkUpdate
    def self.call(user:, ids:, category_id: nil, money_source_id: nil)
      new(user: user, ids: ids, category_id: category_id, money_source_id: money_source_id).call
    end

    attr_reader :updated_count, :error_key

    def initialize(user:, ids:, category_id:, money_source_id:)
      @user = user
      @ids = ids
      @category_id = category_id.presence
      @money_source_id = money_source_id.presence
      @updated_count = 0
      @error_key = nil
    end

    def call
      if parsed_ids.empty?
        @error_key = :no_selection
        return self
      end

      if category_id.nil? && money_source_id.nil?
        @error_key = :nothing_to_change
        return self
      end

      if category_id.present? && !Category.for_user(user).where(id: category_id).exists?
        @error_key = :category_not_found
        return self
      end

      if money_source_id.present? && !user.money_sources.where(id: money_source_id).exists?
        @error_key = :source_not_found
        return self
      end

      scope = user.expenses.where(id: parsed_ids)
      count = scope.count
      if count.zero?
        @error_key = :no_selection
        return self
      end

      updates = {}
      updates[:category_id] = category_id.to_i if category_id.present?
      updates[:money_source_id] = money_source_id.to_i if money_source_id.present?

      @updated_count = scope.update_all(updates)
      self
    end

    def success?
      error_key.nil?
    end

    def failure?
      !success?
    end

    private

    attr_reader :user, :category_id, :money_source_id

    def parsed_ids
      @parsed_ids ||= Array(@ids).flat_map { |value| value.to_s.split(",") }.map(&:to_i).reject(&:zero?)
    end
  end
end
