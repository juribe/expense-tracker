# frozen_string_literal: true

module ExpenseCandidates
  # Bulk-discards many candidates of one user. Only reviewable candidates
  # (needs_review / ready) are discarded; confirmed candidates are never
  # touched.
  #
  #   result = ExpenseCandidates::BulkDiscard.call(user: user, ids: raw_ids)
  #   result.success?         # false on :no_selection
  #   result.discarded_count
  class BulkDiscard
    REVIEWABLE = %w[needs_review ready].freeze

    def self.call(user:, ids:)
      new(user: user, ids: ids).call
    end

    attr_reader :discarded_count, :error_key

    def initialize(user:, ids:)
      @user = user
      @ids = ids
      @discarded_count = 0
      @error_key = nil
    end

    def call
      if parsed_ids.empty?
        @error_key = :no_selection
        return self
      end

      scope = user.expense_candidates.where(id: parsed_ids, status: REVIEWABLE)
      @discarded_count = scope.update_all(status: "discarded", discarded_at: Time.current, updated_at: Time.current)

      if discarded_count.zero?
        @error_key = :no_selection
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

    attr_reader :user

    def parsed_ids
      @parsed_ids ||= Array(@ids).flat_map { |value| value.to_s.split(",") }.map(&:to_i).reject(&:zero?)
    end
  end
end
