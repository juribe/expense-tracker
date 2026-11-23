# frozen_string_literal: true

module Goals
  # Links a virtual goal to a pocket without duplicating savings. The pocket
  # must already hold enough unallocated money to back the goal's virtual
  # balance; every virtual allocation is then moved to that pocket, so the
  # same records continue to be the single source of truth.
  #
  #   Goals::LinkToPocket.call(goal: goal, pocket: pocket, user: current_user)
  class LinkToPocket
    Result = Struct.new(:success, :error, keyword_init: true) do
      def success?
        success
      end
    end

    def self.call(goal:, pocket:, user:)
      new(goal: goal, pocket: pocket, user: user).call
    end

    def initialize(goal:, pocket:, user:)
      @goal = goal
      @pocket = pocket
      @user = user
    end

    def call
      return failure(:missing_goal) if @goal.nil?
      return failure(:missing_pocket) if @pocket.nil?
      return failure(:not_owner) unless @goal.user_id == @user.id && @pocket.user_id == @user.id
      return failure(:not_a_pocket) unless @pocket.pocket? && @pocket.active?
      return failure(:already_linked) if @goal.pocket_id.present? && @goal.pocket_id != @pocket.id

      ActiveRecord::Base.transaction do
        @goal.lock!
        return failure(:already_linked) if @goal.pocket_id.present? && @goal.pocket_id != @pocket.id

        virtual_allocations = @goal.goal_allocations.virtual.order(:created_at, :id).to_a
        virtual_total = virtual_allocations.sum(&:amount).to_d

        if virtual_total.positive? && @pocket.unallocated_amount < virtual_total
          return failure(:insufficient_pocket_balance)
        end

        # Set the destination in memory first: each allocation validates its
        # pocket against the goal's funding target. Positive rows go first so
        # the temporary pocket total never dips below zero when withdrawals
        # are part of the virtual history.
        @goal.allow_pocket_reassignment = true
        @goal.pocket = @pocket
        virtual_allocations.sort_by { |allocation| allocation.amount.to_d.negative? ? 1 : 0 }
                         .each do |allocation|
          allocation.financial_goal = @goal
          allocation.update!(pocket: @pocket)
        end
        @goal.save!
      end

      Result.new(success: true)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success: false, error: e.record.errors.full_messages.first)
    end

    private

    def failure(error)
      Result.new(success: false, error: error)
    end
  end
end
