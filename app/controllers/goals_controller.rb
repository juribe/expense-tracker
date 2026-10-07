# GoalsController
# RESTful for Goal: named savings targets tracked by saved_amount against
# target_amount. Requires a signed-in user; goals are always scoped to
# current_user.
class GoalsController < ApplicationController
  before_action :set_goal, only: [ :edit, :update, :destroy ]

  # GET /goals
  def index
    @goals = current_user.goals.order(:id)
  end

  # GET /goals/new
  def new
    @goal = Goal.new
  end

  # GET /goals/1/edit
  def edit
  end

  # POST /goals
  def create
    @goal = current_user.goals.new(goal_params)

    if @goal.save
      redirect_to goals_path, notice: t("goals.flashes.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /goals/1
  def update
    if @goal.update(goal_params)
      redirect_to goals_path, notice: t("goals.flashes.updated")
    else
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

  def goal_params
    params.require(:goal).permit(:name, :target_amount, :saved_amount, :target_date)
  end
end
