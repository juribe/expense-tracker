# frozen_string_literal: true

module ExpenseCandidates
  # Bulk-updates the category and/or money source of many candidates of one
  # user. Validations mirror the controller's previous rules: category must be
  # one of the user's expense categories and the source must be a payment
  # origin.
  #
  #   result = ExpenseCandidates::BulkUpdate.call(
  #     user: user, ids: raw_ids, category_id: 7, money_source_id: nil
  #   )
  #   result.success?      # false on :no_selection / :nothing_to_change /
  #                        # :category_not_found / :source_not_found
  #   result.updated_count
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

      if category_id.present? && !Category.for_user(user).expenses.where(id: category_id).exists?
        @error_key = :category_not_found
        return self
      end

      if money_source_id.present? && !MoneySource.payment_origins(user).where(id: money_source_id).exists?
        @error_key = :source_not_found
        return self
      end

      scope = user.expense_candidates.where(id: parsed_ids)
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
