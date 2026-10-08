# GoalsController
# RESTful for Goal: named savings targets backed by a Pocket (MoneySource
# kind "pocket"). The pocket's balance is the saved amount — there is no
# manual saved_amount input. Goals are always scoped to current_user.
class GoalsController < ApplicationController
  before_action :set_goal, only: [ :edit, :update, :destroy ]

  # GET /goals
  def index
    @goals = current_user.goals.includes([ :pocket, :goal_allocations ]).order(:id)
  end

  # GET /goals/new
  def new
    @goal = Goal.new
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

  private

  def set_goal
    @goal = current_user.goals.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    flash[:alert] = t("goals.not_found", default: "Meta no encontrada")
    redirect_to goals_path
  end

  # Pockets offered when creating a goal: never created implicitly. When the
  # user has none, the form shows a link to create one first.
  def load_pockets
    @pockets = current_user.money_sources.pockets.active.order(:name)
  end

  def goal_params
    params.require(:goal).permit(:name, :target_amount, :target_date,
                                 :pocket_id, :priority, :category, :status)
  end
end
