# GoalAllocationsController
# Internal reservations of Pocket money to Financial Goals. These are not
# financial movements: creating or destroying an allocation never touches
# the pocket's balance, expenses or income. `create` assigns (+) or releases
# (-) pocket money to/from a goal; `reallocate` moves a reservation between
# two goals of the same pocket via compensating allocations.
class GoalAllocationsController < ApplicationController
  rescue_from ActiveRecord::RecordNotFound do
    head :not_found
  end

  # POST /goal_allocations
  def create
    goal = user_goals.find(allocation_goal_id)
    allocation = goal.goal_allocations.build(allocation_params)

    if allocation.save
      flash_key = allocation.amount.to_d.positive? ? "goals.flashes.allocated" : "goals.flashes.released"
      redirect_back fallback_location: goals_path, notice: t(flash_key)
    else
      redirect_back fallback_location: goals_path, alert: allocation.errors.full_messages.first
    end
  end

  # DELETE /goal_allocations/:id — removes one reservation record; the
  # reserved money returns to the pocket's unallocated pool.
  def destroy
    allocation = GoalAllocation.joins(:financial_goal).where(financial_goal: { user_id: current_user.id }).find(params[:id])
    allocation.destroy
    redirect_back fallback_location: goals_path, notice: t("goals.flashes.allocation_deleted")
  end

  # POST /goal_allocations/reallocate
  def reallocate
    goals = user_goals.where(id: [ params[:from_goal_id], params[:to_goal_id] ])
    goal_from = goals.find { |g| g.id == params[:from_goal_id].to_i }
    goal_to = goals.find { |g| g.id == params[:to_goal_id].to_i }

    result = GoalAllocations::Reallocate.call(goal_from: goal_from, goal_to: goal_to, amount: params[:amount], user: current_user)
    if result[:ok]
      redirect_back fallback_location: goals_path, notice: t("goals.flashes.reallocated")
    else
      redirect_back fallback_location: goals_path, alert: t("goals.reallocate_errors.#{result[:error]}", default: t("goals.reallocate_errors.invalid"))
    end
  end

  private

  def user_goals
    current_user.goals
  end

  # Accept the params under either naming (form_with derives the scope from
  # the model class name "goal_allocation"; the views pin it to
  # "goal_allocations" for consistency).
  def allocation_payload
    params[:goal_allocations].presence || params[:goal_allocation].presence || params
  end

  def allocation_goal_id
    allocation_payload[:financial_goal_id]
  end

  def allocation_params
    allocation_payload.permit(:financial_goal_id, :amount, :date, :note)
  end
end
