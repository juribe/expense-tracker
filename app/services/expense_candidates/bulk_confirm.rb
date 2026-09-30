# frozen_string_literal: true

module ExpenseCandidates
  # Confirms many candidates of one user into expenses, optionally applying a
  # category/money source first. Partial failures (missing fields, invalid
  # records) are reported per candidate instead of aborting the batch.
  #
  #   result = ExpenseCandidates::BulkConfirm.call(
  #     user: user, ids: raw_ids, category_id: nil, money_source_id: nil
  #   )
  #   result.success?        # false on :no_selection / :category_not_found /
  #                          # :source_not_found
  #   result.confirmed_count # candidates that became expenses
  #   result.errors          # [{ id:, description:, errors: [...] }]
  class BulkConfirm
    def self.call(user:, ids:, category_id: nil, money_source_id: nil)
      new(user: user, ids: ids, category_id: category_id, money_source_id: money_source_id).call
    end

    attr_reader :confirmed_count, :errors, :error_key

    def initialize(user:, ids:, category_id:, money_source_id:)
      @user = user
      @ids = ids
      @category_id = category_id.present? ? category_id.to_i : nil
      @money_source_id = money_source_id.present? ? money_source_id.to_i : nil
      @confirmed_count = 0
      @errors = []
      @error_key = nil
    end

    def call
      if parsed_ids.empty?
        @error_key = :no_selection
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

      user.expense_candidates.where(id: parsed_ids).find_each do |candidate|
        candidate.update(category_id: category_id, money_source_id: money_source_id) if category_id || money_source_id
        candidate.recalculate_missing_fields!
        candidate.recalculate_status!

        if candidate.missing_fields.any?
          @errors << {
            id: candidate.id,
            description: candidate.description,
            errors: ["Campos faltantes: #{candidate.missing_fields.join(', ')}"]
          }
          next
        end

        candidate.confirm!
        @confirmed_count += 1
      rescue ActiveRecord::RecordInvalid => e
        @errors << { id: candidate.id, description: candidate.description, errors: [e.message] }
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

    attr_reader :user, :category_id, :money_source_id

    def parsed_ids
      @parsed_ids ||= Array(@ids).flat_map { |value| value.to_s.split(",") }.map(&:to_i).reject(&:zero?)
    end
  end
end
