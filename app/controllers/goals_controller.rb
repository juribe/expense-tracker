# GoalsController
# RESTful for Goal. In simple mode a goal is virtual and its ledger rows have
# no pocket; in advanced mode a goal remains backed by a Pocket (MoneySource
# kind "pocket"). The saved amount is always derived from GoalAllocation.
# Goals are always scoped to current_user.
class GoalsController < ApplicationController
  before_action :require_detailed_money_tracking, only: :link_to_pocket
  before_action :set_goal, only: [ :edit, :update, :destroy, :complete, :link_to_pocket ]

  # GET /goals
  def index
    @goals = goals_scope.order(:created_at, :id)
    load_pockets
  end

  # GET /goals/new
  # Accepts optional name/target_amount params so the savings simulator can
  # reuse this form instead of introducing a separate goals system.
  def new
    @goal = Goal.new(name: params[:name].presence, target_amount: params[:target_amount].presence)
    load_pockets
  end

  # GET /goals/1/edit
  def edit
    load_pockets
  end

  # POST /goals
  def create
    @goal = current_user.goals.new(goal_params)

    if @goal.save
      redirect_to goals_path, notice: t("goals.flashes.created")
    else
      load_pockets
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /goals/1
  def update
    if @goal.update(goal_params)
      redirect_to goals_path, notice: t("goals.flashes.updated")
    else
      load_pockets
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /goals/1
  def destroy
    @goal.destroy
    redirect_to goals_path, notice: t("goals.flashes.destroyed")
  end

  # PATCH /goals/:id/complete
  def complete
    result = Goals::Complete.call(goal: @goal)
    if result.success?
      redirect_to goals_path, notice: t("goals.flashes.completed")
    else
      redirect_to goals_path, alert: t("goals.complete_errors.#{result.error}", default: t("goals.complete_errors.target_not_reached"))
    end
  end

  # PATCH /goals/:id/link_to_pocket
  def link_to_pocket
    pocket = current_user.money_sources.pockets.active.find_by(id: params[:pocket_id])
    result = Goals::LinkToPocket.call(goal: @goal, pocket: pocket, user: current_user)

    if result.success?
      redirect_to goals_path, notice: t("goals.flashes.linked_to_pocket")
    else
      redirect_to goals_path, alert: t("goals.link_errors.#{result.error}", default: t("goals.link_errors.invalid"))
    end
  end

  private

  def set_goal
    @goal = current_user.goals.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    flash[:alert] = t("goals.not_found", default: "Meta no encontrada")
    redirect_to goals_path
  end

  # Pockets offered when creating a goal: never created implicitly. Simple
  # goals are virtual and never touch this collection.
  def load_pockets
    @pockets = money_tracking_detailed? ? current_user.money_sources.pockets.active.order(:name) : []
  end

  def goals_scope
    includes = money_tracking_detailed? ? [ :pocket, :goal_allocations ] : [ :goal_allocations ]
    current_user.goals.includes(includes)
  end

  def goal_params
    permitted = [ :name, :target_amount, :target_date, :priority, :category, :status ]
    permitted << :pocket_id if money_tracking_detailed?
    params.require(:goal).permit(*permitted)
  end
end
