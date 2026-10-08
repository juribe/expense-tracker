# frozen_string_literal: true

module GoalAllocations
  # Moves a reserved amount from one goal to another inside the same pocket.
  # Nothing leaves the pocket and no financial movement happens: it is a
  # pair of compensating allocations (-X on the origin, +X on the destiny)
  # written atomically so the audit history stays intact.
  #
  #   GoalAllocations::Reallocate.call(goal_from:, goal_to:, amount:, user:)
  #   => { ok: true } or { ok: false, error: :different_pockets }
  class Reallocate
    def self.call(goal_from:, goal_to:, amount:, user:)
      new(goal_from, goal_to, amount, user).call
    end

    def initialize(goal_from, goal_to, amount, user)
      @goal_from = goal_from
      @goal_to = goal_to
      @amount = amount
      @user = user
    end

    def call
      return failure(:missing_goals) if @goal_from.nil? || @goal_to.nil?
      return failure(:same_goal) if @goal_from.id == @goal_to.id
      return failure(:different_pockets) unless same_pocket?
      return failure(:not_owner) unless owned_by_user?

      amount = parse_amount
      return failure(:invalid_amount) unless amount&.positive?

      date = Date.current
      ActiveRecord::Base.transaction do
        @goal_from.goal_allocations.create!(pocket: @goal_from.pocket, amount: -amount, date: date)
        @goal_to.goal_allocations.create!(pocket: @goal_to.pocket, amount: amount, date: date)
      end

      { ok: true }
    rescue ActiveRecord::RecordInvalid
      failure(:invalid)
    end

    private

    def same_pocket?
      @goal_from.pocket_id == @goal_to.pocket_id
    end

    def owned_by_user?
      @goal_from.user_id == @user.id && @goal_to.user_id == @user.id
    end

    def parse_amount
      normalized = MoneyFormat.normalize(@amount)
      normalized.present? ? normalized.to_d : nil
    end

    def failure(code)
      { ok: false, error: code }
    end
  end
end
